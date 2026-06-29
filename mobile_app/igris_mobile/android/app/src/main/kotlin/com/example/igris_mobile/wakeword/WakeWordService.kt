package com.example.igris_mobile.wakeword

import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Always-listening foreground service that:
 *   - holds an AudioRecord capturing 16 kHz mono PCM
 *   - delegates inference to [WakeWordEngine]
 *   - exposes its lifecycle to [WakeWordPlugin] via local binding
 *   - handles ACTION_AUDIO_BECOMING_NOISY (headphone unplug) by pausing
 *   - handles phone-state transitions by pausing
 *
 * Manifest declaration (see INTEGRATION_GUIDE.md):
 *
 *   <service
 *       android:name=".wakeword.WakeWordService"
 *       android:exported="false"
 *       android:foregroundServiceType="microphone">
 *     <property
 *         android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
 *         android:value="always_listening_wake_word" />
 *   </service>
 */
class WakeWordService : Service() {

    private val binder = LocalBinder()
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "igris-wakeword").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val running = AtomicBoolean(false)
    private val phoneStatePaused = AtomicBoolean(false)
    private val noisyPaused = AtomicBoolean(false)

    private var audioRecord: AudioRecord? = null
    private var engine: WakeWordEngine? = null
    private var ringBuffer: AudioRingBuffer? = null
    private var detectionListener: ((WakeWordEngine.Detection) -> Unit)? = null
    private var errorListener: ((String, String) -> Unit)? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var modelPath: String? = null
    private var sensitivity: Float = 0.5f
    private var phoneStateListener: PhoneStateListener? = null

    inner class LocalBinder : Binder() {
        fun service(): WakeWordService = this@WakeWordService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        registerPhoneStateListener()
        registerNoisyReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            WakeWordNotification.ACTION_STOP -> {
                stopListening()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // START_STICKY so the OS can restart us if it kills us for memory
        // pressure while the user still wants the listener enabled. The plugin
        // will re-attach via the EventChannel on the Dart side.
        return START_STICKY
    }

    /**
     * Configure and start the listener. Idempotent: a second call with the
     * same modelPath is a no-op. Changing the modelPath restarts the engine.
     */
    fun start(
        modelPath: String,
        sensitivity: Float,
        onDetection: (WakeWordEngine.Detection) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        if (running.get()) {
            if (this.modelPath == modelPath && this.sensitivity == sensitivity) return
            // Configuration changed — restart.
            stopInternal()
        }
        this.modelPath = modelPath
        this.sensitivity = sensitivity.coerceIn(0f, 1f)
        this.detectionListener = onDetection
        this.errorListener = onError

        // Promote to foreground BEFORE acquiring the mic (Android 14+ requires
        // the microphone FGS type to be set before record() is called).
        try {
            WakeWordNotification.startForeground(this)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start foreground", t)
            onError("FGS_START_FAILED", t.message ?: "unknown")
            stopSelf()
            return
        }

        executor.execute {
            try {
                initializeEngine()
                startAudioCapture()
                running.set(true)
                Log.i(TAG, "Wake word listener running (model=$modelPath, sensitivity=$sensitivity)")
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to start listener", t)
                onError("START_FAILED", "${t.javaClass.simpleName}: ${t.message}")
                stopInternal()
            }
        }
    }

    fun stopListening() {
        executor.execute { stopInternal() }
    }

    fun setSensitivity(sensitivity: Float) {
        this.sensitivity = sensitivity.coerceIn(0f, 1f)
        engine?.setThreshold(this.sensitivity)
    }

    fun isRunning(): Boolean = running.get()

    private fun initializeEngine() {
        val path = modelPath ?: error("modelPath is null")
        val eng = WakeWordEngine(path, sensitivity) { detection ->
            // Acquire a short wake lock so post-detection STT/TTS doesn't get
            // preempted by the Doze cycle on Android 12+.
            acquireShortWakeLock()
            detectionListener?.invoke(detection)
        }
        ringBuffer = AudioRingBuffer(frameSize = eng.inputSize)
        engine = eng
    }

    private fun startAudioCapture() {
        val sampleRate = 16_000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT

        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding)
        if (minBuffer <= 0) {
            throw IllegalStateException("AudioRecord.getMinBufferSize returned $minBuffer")
        }
        // 4× the minimum so we don't drop frames under load.
        val bufferSize = minBuffer * 4

        @Suppress("MissingPermission") // caller is responsible for RECORD_AUDIO check
        val record = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(encoding)
                        .setChannelMask(channelConfig)
                        .build(),
                )
                .setBufferSizeInBytes(bufferSize)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                encoding,
                bufferSize,
            )
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("AudioRecord failed to initialize")
        }
        // Pin to built-in mic if a BT headset is connected.
        preferBuiltInMic(record)
        record.startRecording()
        audioRecord = record

        val readBuffer = ShortArray(640) // 40 ms at 16 kHz; we accumulate into frames
        while (running.get()) {
            if (phoneStatePaused.get() || noisyPaused.get()) {
                // Drain the read briefly to keep the buffer fresh; then idle.
                try { Thread.sleep(80) } catch (_: InterruptedException) { break }
                continue
            }
            val n = record.read(readBuffer, 0, readBuffer.size)
            if (n <= 0) continue
            val rb = ringBuffer ?: continue
            rb.write(readBuffer, n)

            val eng = engine ?: continue
            val frame = rb.latestFrame() ?: continue
            try {
                eng.processFrame(frame, rb)
            } catch (t: Throwable) {
                Log.e(TAG, "Inference failed", t)
                errorListener?.invoke("INFERENCE_FAILED", "${t.javaClass.simpleName}: ${t.message}")
                // Continue running — transient OOM should not kill the service.
            }
        }
    }

    private fun stopInternal() {
        if (!running.getAndSet(false)) return
        try { audioRecord?.stop() } catch (_: Throwable) {}
        try { audioRecord?.release() } catch (_: Throwable) {}
        audioRecord = null
        try { engine?.close() } catch (_: Throwable) {}
        engine = null
        ringBuffer?.reset()
        WakeWordNotification.stopForeground(this)
        Log.i(TAG, "Wake word listener stopped")
    }

    override fun onDestroy() {
        stopInternal()
        try { phoneStateListener?.let {
            @Suppress("DEPRECATION")
            (getSystemService(TELEPHONY_SERVICE) as? TelephonyManager)?.listen(it, PhoneStateListener.LISTEN_NONE)
        } } catch (_: Throwable) {}
        executor.shutdownNow()
        try { noisyReceiver?.let { unregisterReceiver(it) } } catch (_: Throwable) {}
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The user swiped the app away. We stay alive because we're a foreground
        // service with a notification; the user can stop us from there.
        super.onTaskRemoved(rootIntent)
    }

    // ---- helpers ----

    private fun acquireShortWakeLock() {
        try {
            val pm = ContextCompat.getSystemService(this, PowerManager::class.java) ?: return
            val lock = wakeLock ?: pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG,
            ).apply {
                setReferenceCounted(false)
                wakeLock = this
            }
            lock.acquire(3_000L) // 3s is plenty for post-detection STT
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to acquire wake lock", t)
        }
    }

    private fun preferBuiltInMic(record: AudioRecord) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val builtIn = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC } ?: return
        try { record.setPreferredDevice(builtIn) } catch (_: Throwable) {}
    }


    private var noisyReceiver: android.content.BroadcastReceiver? = null

    private fun registerNoisyReceiver() {
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                        Log.i(TAG, "Headphones unplugged — pausing listener briefly")
                        noisyPaused.set(true)
                        // Resume after 1.5s — the OS usually finishes its
                        // rerouting in that window.
                        executor.execute {
                            try { Thread.sleep(1_500) } catch (_: InterruptedException) {}
                            noisyPaused.set(false)
                        }
                    }
                }
            }
        }
        val filter = android.content.IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        noisyReceiver = receiver
    }

    @Suppress("DEPRECATION")
    private fun registerPhoneStateListener() {
        val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager ?: return
        val listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                when (state) {
                    TelephonyManager.CALL_STATE_OFFHOOK,
                    TelephonyManager.CALL_STATE_RINGING -> phoneStatePaused.set(true)
                    TelephonyManager.CALL_STATE_IDLE -> {
                        if (phoneStatePaused.getAndSet(false)) {
                            // Resume after 1s so the audio routing settles.
                            executor.execute {
                                try { Thread.sleep(1_000) } catch (_: InterruptedException) {}
                            }
                        }
                    }
                }
            }
        }
        tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        phoneStateListener = listener
    }

    companion object {
        private const val TAG = "WakeWordService"
        private const val WAKE_LOCK_TAG = "igris::wakeword_detect"

        fun start(context: Context) {
            val intent = Intent(context, WakeWordService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, WakeWordService::class.java).setAction(WakeWordNotification.ACTION_STOP)
            context.startService(intent)
        }
    }
}
