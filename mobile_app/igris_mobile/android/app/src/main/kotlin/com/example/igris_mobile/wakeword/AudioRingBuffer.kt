package com.example.igris_mobile.wakeword

import java.util.concurrent.atomic.AtomicReference

/**
 * Lock-free single-producer / single-consumer ring buffer for 16-bit PCM samples.
 *
 * The audio capture thread calls [write] once per [AudioRecord.read] call.
 * The inference thread calls [latestFrame] to obtain the most recent
 * [frameSize] samples aligned to a [frameSize] boundary (or `null` if not
 * enough data is available yet).
 *
 * The buffer also retains a short trailing window in [recentWindow] so that
 * on a positive detection we can emit the audio that *preceded* the trigger
 * — that's the audio SttFollowupService will start from.
 *
 * Capacity is fixed at construction. Total memory for the default
 * `frameSize=1280, windowMs=1500` at 16 kHz is about 60 KB — negligible.
 */
class AudioRingBuffer(
    private val frameSize: Int,
    windowMs: Int = 1500,
    sampleRate: Int = 16_000,
) {
    private val capacity: Int = ((sampleRate * windowMs) / 1000).coerceAtLeast(frameSize * 4)
    private val buffer = ShortArray(capacity)
    private val head = AtomicReference(0L) // monotonic write index (total samples written)

    /** Append [data] of length [length] (≤ `data.size`). */
    fun write(data: ShortArray, length: Int) {
        if (length <= 0) return
        val h = head.get()
        val start = (h.toInt() % capacity)
        val firstChunk = minOf(length, capacity - start)
        System.arraycopy(data, 0, buffer, start, firstChunk)
        if (firstChunk < length) {
            System.arraycopy(data, firstChunk, buffer, 0, length - firstChunk)
        }
        head.set(h + length)
    }

    /**
     * Returns the most recent [frameSize] samples, or `null` if we haven't
     * captured that many yet. The returned array is reused; copy if you need
     * to retain it past the next call.
     */
    fun latestFrame(): ShortArray? {
        val h = head.get()
        if (h < frameSize) return null
        val out = ShortArray(frameSize)
        val end = (h.toInt() % capacity)
        // We want samples [h - frameSize, h), wrapping around the ring.
        var srcIdx = end - frameSize
        if (srcIdx < 0) srcIdx += capacity
        val firstChunk = minOf(frameSize, capacity - srcIdx)
        System.arraycopy(buffer, srcIdx, out, 0, firstChunk)
        if (firstChunk < frameSize) {
            System.arraycopy(buffer, 0, out, firstChunk, frameSize - firstChunk)
        }
        return out
    }

    /**
     * Returns the last [millis] milliseconds of audio as a fresh short array.
     * Used when emitting a detection so the Dart side can hand it to the
     * post-wake STT pipeline.
     */
    fun recentWindow(millis: Int, sampleRate: Int = 16_000): ShortArray {
        val samples = ((sampleRate * millis) / 1000).coerceAtMost(capacity)
        val out = ShortArray(samples)
        val h = head.get()
        if (h < samples) {
            // Buffer not yet full; return what we have.
            val firstChunk = minOf(h.toInt(), capacity)
            System.arraycopy(buffer, 0, out, samples - firstChunk, firstChunk)
            return out
        }
        val end = (h.toInt() % capacity)
        var srcIdx = end - samples
        if (srcIdx < 0) srcIdx += capacity
        val firstChunk = minOf(samples, capacity - srcIdx)
        System.arraycopy(buffer, srcIdx, out, 0, firstChunk)
        if (firstChunk < samples) {
            System.arraycopy(buffer, 0, out, firstChunk, samples - firstChunk)
        }
        return out
    }

    fun totalSamplesWritten(): Long = head.get()

    fun reset() {
        head.set(0L)
    }
}
