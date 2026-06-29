package com.example.igris_mobile.wakeword

import android.util.Log
import org.tensorflow.lite.InterpreterApi
import org.tensorflow.lite.InterpreterApi.Options
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Loads a TFLite "Hey IGRIS" wake word model and runs it on 80 ms frames of
 * 16 kHz mono PCM.
 *
 * Model contract (matches openWakeWord's exported combined model):
 *   - Input shape: [1, N] float32, where N = [inputSize] (default 1280 samples = 80 ms)
 *   - Output shape: [1, numClasses] float32, ordered:
 *       [0] = "hey_igris"  (positive class)
 *       [1..N-1] = negative/spotter classes for false-positive rejection
 *   - Sample rate: 16 kHz
 *   - Quantization: float32 (post-training quantization optional)
 *
 * The melspectrogram frontend is baked into the model — input is raw PCM.
 *
 * VAD gate: a rolling RMS baseline is computed from the last [vadWindowMs]
 * of audio. Frames whose RMS is below [vadMultiplier] × baseline are
 * silently dropped before reaching the interpreter, which is the single
 * biggest battery win.
 *
 * Throttling: see [DetectionThrottler]. The engine doesn't emit raw scores
 * to Dart — only "I am > [debounce] consecutive frames confident" events.
 */
class WakeWordEngine(
    modelPath: String,
    initialThreshold: Float,
    private val onDetection: (Detection) -> Unit,
) : AutoCloseable {

    /**
     * The expected model input length in samples. 1280 = 80 ms at 16 kHz,
     * which is openWakeWord's default. If your model uses a different
     * size, we read it from the interpreter's input shape.
     */
    var inputSize: Int = 1280
        private set

    /**
     * Number of output classes. We assume:
     *   - index 0 is the positive class
     *   - the rest are negative / spotter classes
     * If your model has a different layout, the [DetectionThrottler] still
     * works as long as the positive class is at index 0.
     */
    var numClasses: Int = 1
        private set

    private val interpreter: InterpreterApi
    private val inputBuffer: ByteBuffer
    private val outputBuffer: Array<FloatArray>
    private val throttler = DetectionThrottler(initialThreshold)
    private val vadWindow = VADWindow(windowMs = 2_000, sampleRate = 16_000)
    private val rmsFloor = 0.005f // absolute floor for very quiet rooms
    private val vadMultiplier = 1.2f

    init {
        val model = loadModelFile(modelPath)
        val opts = Options().apply {
            // XNNPACK is the right delegate for a model this small. It's the
            // default on Android, but we set it explicitly to make the intent
            // clear and to make it easy to swap in NNAPI for older devices.
            setNumThreads(1)
            setUseXNNPACK(true)
        }
        interpreter = InterpreterApi.create(model, opts)

        // Read input shape from the model itself so we adapt to whatever
        // openWakeWord exports (it sometimes uses [1, 16, 96] for spectrograms,
        // sometimes [1, 1280] for raw PCM).
        val inShape = interpreter.getInputTensor(0).shape()
        val inBytes = interpreter.getInputTensor(0).dataType().byteSize()
        val flatInput = inShape.fold(1) { a, b -> a * b }
        inputSize = flatInput
        inputBuffer = ByteBuffer.allocateDirect(flatInput * inBytes).order(ByteOrder.nativeOrder())

        val outShape = interpreter.getOutputTensor(0).shape()
        numClasses = outShape.fold(1) { a, b -> a * b }
        outputBuffer = Array(1) { FloatArray(numClasses) }

        Log.i(TAG, "Model loaded: input=${inShape.contentToString()} output=${outShape.contentToString()}")
    }

    /**
     * Process a single [frame] of PCM samples. The [ringBuffer] is used to
     * grab the trailing audio on a positive detection (so the Dart side can
     * hand the user's actual utterance to the post-wake STT pipeline).
     */
    fun processFrame(frame: ShortArray, ringBuffer: AudioRingBuffer) {
        // VAD: compute RMS and decide whether to run inference.
        val rms = computeRms(frame)
        vadWindow.add(rms)
        val baseline = max(vadWindow.baseline(), rmsFloor)
        if (rms < baseline * vadMultiplier) {
            // Below ambient noise floor — don't bother running the model.
            // We still tick the throttler so it doesn't lock on a stale score.
            throttler.onSilence()
            return
        }

        // Normalize int16 → float32 in roughly [-1, 1] and copy into the
        // direct ByteBuffer. TFLite reads from the buffer's current position.
        inputBuffer.rewind()
        val scale = 1.0f / 32_768.0f
        for (s in frame) {
            inputBuffer.putFloat(s * scale)
        }
        inputBuffer.rewind()

        try {
            interpreter.run(inputBuffer, outputBuffer)
        } catch (t: Throwable) {
            // Don't crash the service on a single bad frame.
            Log.w(TAG, "interpreter.run failed", t)
            return
        }

        val scores = outputBuffer[0]
        val positive = scores[0]
        val maxNegative = scores.drop(1).maxOrNull() ?: 0f
        // We accept the detection only if the positive class beats every
        // negative class by a comfortable margin. This is the standard
        // openWakeWord false-positive rejection heuristic.
        val accepted = positive - maxNegative
        throttler.offer(accepted) { score ->
            // Build the detection payload: include a 1.5s audio clip.
            val clip = ringBuffer.recentWindow(millis = 1_500)
            onDetection(
                Detection(
                    score = score,
                    threshold = throttler.threshold,
                    capturedAtMs = System.currentTimeMillis(),
                    audioSamples = clip,
                    sampleRate = 16_000,
                ),
            )
        }
    }

    fun setThreshold(threshold: Float) {
        throttler.threshold = threshold.coerceIn(0f, 1f)
    }

    override fun close() {
        try { interpreter.close() } catch (_: Throwable) {}
    }

    // ---- utilities ----

    private fun loadModelFile(path: String): MappedByteBuffer {
        val fd = FileInputStream(path).channel
        return fd.map(FileChannel.MapMode.READ_ONLY, 0, fd.size())
    }

    private fun computeRms(samples: ShortArray): Float {
        if (samples.isEmpty()) return 0f
        var sumSq = 0.0
        for (s in samples) {
            val f = s.toFloat()
            sumSq += f * f
        }
        return sqrt(sumSq / samples.size).toFloat()
    }

    data class Detection(
        val score: Float,
        val threshold: Float,
        val capturedAtMs: Long,
        val audioSamples: ShortArray,
        val sampleRate: Int,
    ) {
        // Auto-generated equals/hashCode that handle the array.
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Detection) return false
            if (score != other.score) return false
            if (threshold != other.threshold) return false
            if (capturedAtMs != other.capturedAtMs) return false
            if (!audioSamples.contentEquals(other.audioSamples)) return false
            if (sampleRate != other.sampleRate) return false
            return true
        }
        override fun hashCode(): Int {
            var r = score.hashCode()
            r = 31 * r + threshold.hashCode()
            r = 31 * r + capturedAtMs.hashCode()
            r = 31 * r + audioSamples.contentHashCode()
            r = 31 * r + sampleRate
            return r
        }
    }

    companion object {
        private const val TAG = "WakeWordEngine"
    }
}

/**
 * Maintains a rolling baseline of the RMS over a sliding window. Used to
 * decide whether a frame is "above ambient noise" and worth feeding to the
 * wake word model.
 */
internal class VADWindow(private val windowMs: Int, private val sampleRate: Int) {
    private val capacity: Int = ((sampleRate * windowMs) / 1000).coerceAtLeast(64)
    private val samples = FloatArray(capacity)
    private var head = 0
    private var filled = 0

    fun add(rms: Float) {
        samples[head] = rms
        head = (head + 1) % capacity
        if (filled < capacity) filled++
    }

    /**
     * The 25th-percentile of the window — i.e. a "quiet room" baseline
     * that's robust to occasional speech/door-slam spikes.
     */
    fun baseline(): Float {
        if (filled == 0) return 0f
        val sorted = FloatArray(filled) { samples[it] }
        java.util.Arrays.sort(sorted, 0, filled)
        val q = (filled * 0.25f).toInt().coerceIn(0, filled - 1)
        return sorted[q]
    }
}
