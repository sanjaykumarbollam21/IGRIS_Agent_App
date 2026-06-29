package com.example.igris_mobile.wakeword

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Flutter ↔ Kotlin bridge for the "Hey IGRIS" wake word listener.
 *
 * Exposes:
 *   - MethodChannel("igris/wake_word/ctrl")
 *       start({modelPath, sensitivity}) -> {ok}
 *       stop()                          -> {ok}
 *       setSensitivity(0..1)            -> {ok}
 *       isListening()                   -> {running: bool}
 *       checkPermissions()              -> {mic, notifications, allGranted}
 *       requestPermissions()            -> {}  (async via system dialog)
 *       openNotificationSettings()      -> {}
 *       requestIgnoreBatteryOptim()     -> {}
 *
 *   - EventChannel("igris/wake_word/events")
 *       Emits a Map per event:
 *         {type: "status",   state: "starting"|"listening"|"stopped"|"error", ...}
 *         {type: "detection", score, threshold, audioBase64, sampleRate}
 *         {type: "error",     code, message}
 *
 * Detection payloads include a 1.5s trailing audio clip (16 kHz mono int16
 * PCM, base64-encoded) so the Dart side can hand it directly to
 * SttFollowupService for "Hey IGRIS, what's the weather" → STT.
 */
class WakeWordPlugin : FlutterPlugin, ActivityAware {

    private var context: Context? = null
    private var activity: Activity? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "igris-wakeword-io")
    }

    private var service: WakeWordService? = null
    private var bound = false

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val b = binder as? WakeWordService.LocalBinder ?: return
            service = b.service()
            bound = true
            Log.i(TAG, "Service bound")
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            bound = false
            Log.w(TAG, "Service disconnected")
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_CTRL).also { ch ->
            ch.setMethodCallHandler(::onMethodCall)
        }
        eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_EVENT).also { ch ->
            ch.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        teardown()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // ---- method channel ----

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> handleStart(call, result)
            "stop" -> handleStop(result)
            "setSensitivity" -> handleSetSensitivity(call, result)
            "isListening" -> result.success(mapOf("running" to (service?.isRunning() == true)))
            "checkPermissions" -> handleCheckPermissions(result)
            "requestPermissions" -> handleRequestPermissions(result)
            "openNotificationSettings" -> {
                context?.let { PermissionsHelper.openAppNotificationSettings(it) }
                result.success(null)
            }
            "requestIgnoreBatteryOptim" -> {
                activity?.let { PermissionsHelper.requestIgnoreBatteryOptimizations(it) }
                result.success(null)
            }
            "isIgnoringBatteryOptimizations" -> {
                result.success(mapOf("ignored" to (context?.let { PermissionsHelper.isIgnoringBatteryOptimizations(it) } ?: false)))
            }
            "version" -> result.success(mapOf(
                "engine" to "openWakeWord+tflite",
                "tflite_min" to "2.14.0",
            ))
            else -> result.notImplemented()
        }
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Plugin not attached", null)
        val modelPath = call.argument<String>("modelPath")
        if (modelPath.isNullOrBlank()) {
            return result.error("BAD_ARGS", "modelPath is required", null)
        }
        // The Dart side can pass either an absolute file path (preferred —
        // fileProvider-safe on Android 11+) or a Flutter asset key, in which
        // case we copy from app assets to a cache file once and cache it.
        val absolutePath = resolveModelPath(ctx, modelPath)
        if (absolutePath == null || !File(absolutePath).exists()) {
            emitStatus("error", mapOf("code" to "MODEL_MISSING", "message" to "Model file not found: $modelPath"))
            return result.error("MODEL_MISSING", "Model file not found: $modelPath", null)
        }
        val sensitivity = (call.argument<Double>("sensitivity") ?: 0.5).toFloat()
        emitStatus("starting", mapOf("model" to absolutePath, "sensitivity" to sensitivity))
        // Start the foreground service and bind to it.
        try {
            val intent = Intent(ctx, WakeWordService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        } catch (t: Throwable) {
            emitStatus("error", mapOf("code" to "FGS_START_FAILED", "message" to (t.message ?: "unknown")))
            return result.error("FGS_START_FAILED", t.message, null)
        }
        bindServiceIfNeeded()
        // Hand the start call to the service. If the service isn't bound yet,
        // queue the call so it runs as soon as the binder arrives.
        fun startRunnable() {
            val svc = service
            if (svc == null) {
                mainHandler.postDelayed({ startRunnable() }, 100)
            } else {
                svc.start(absolutePath, sensitivity, ::onDetection, ::onError)
                emitStatus("listening", mapOf("sensitivity" to sensitivity))
            }
        }
        startRunnable()

        result.success(mapOf("ok" to true, "modelPath" to absolutePath))
    }

    private fun handleStop(result: MethodChannel.Result) {
        emitStatus("stopping", null)
        service?.stopListening()
        if (bound) {
            try {
                context?.unbindService(connection)
            } catch (_: Throwable) {}
            bound = false
            service = null
        }
        // Also stop the FGS itself.
        context?.let { WakeWordService.stop(it) }
        emitStatus("stopped", null)
        result.success(mapOf("ok" to true))
    }

    private fun handleSetSensitivity(call: MethodCall, result: MethodChannel.Result) {
        val s = (call.argument<Double>("sensitivity") ?: return result.error("BAD_ARGS", "sensitivity required", null)).toFloat()
        service?.setSensitivity(s)
        result.success(mapOf("ok" to true))
    }

    private fun handleCheckPermissions(result: MethodChannel.Result) {
        val ctx = context ?: return result.success(emptyMap<String, Any>())
        val mic = PermissionsHelper.hasMic(ctx)
        val notif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            !PermissionsHelper.notificationsAreBlocked(ctx)
        } else true
        result.success(mapOf(
            "mic" to mic,
            "notifications" to notif,
            "allGranted" to (mic && notif),
            "batteryIgnored" to PermissionsHelper.isIgnoringBatteryOptimizations(ctx),
        ))
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        val act = activity ?: return result.error("NO_ACTIVITY", "Activity not attached", null)
        PermissionsHelper.requestAll(act)
        result.success(null)
    }

    // ---- event emission ----

    private fun emitStatus(state: String, extras: Map<String, Any?>?) {
        val payload = HashMap<String, Any?>(2)
        payload["type"] = "status"
        payload["state"] = state
        extras?.forEach { (k, v) -> payload[k] = v }
        postToEventSink(payload)
    }

    private fun onDetection(detection: WakeWordEngine.Detection) {
        // Run on a background thread to keep the audio path off the main
        // thread; the event sink is thread-safe.
        ioExecutor.execute {
            val payload = HashMap<String, Any?>()
            payload["type"] = "detection"
            payload["score"] = detection.score.toDouble()
            payload["threshold"] = detection.threshold.toDouble()
            payload["capturedAtMs"] = detection.capturedAtMs
            payload["sampleRate"] = detection.sampleRate
            // Encode 1.5s of int16 PCM as base64 — ~48 KB for 16 kHz mono.
            // Hand it straight to the Dart side, which can decode and feed
            // SttFollowupService / Vosk / whisper.cpp.
            payload["audioBase64"] = Base64.encodeToString(
                shortsToBytes(detection.audioSamples),
                Base64.NO_WRAP,
            )
            postToEventSink(payload)
        }
    }

    private fun onError(code: String, message: String) {
        val payload = HashMap<String, Any?>()
        payload["type"] = "error"
        payload["code"] = code
        payload["message"] = message
        postToEventSink(payload)
    }

    private fun postToEventSink(payload: Map<String, Any?>) {
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (t: Throwable) {
                Log.w(TAG, "eventSink failed", t)
            }
        }
    }

    // ---- model path resolution ----

    /**
     * Resolve a model path supplied by Dart. We accept:
     *   1. An absolute filesystem path (preferred — used when the Dart side
     *      has already copied the asset to a cache file)
     *   2. A Flutter asset key like "assets/wake_word/hey_igris.tflite",
     *      which we copy to a cache file the first time and return the
     *      cached path on subsequent calls.
     */
    private fun resolveModelPath(ctx: Context, requested: String): String? {
        val asFile = File(requested)
        if (asFile.isAbsolute && asFile.exists()) return asFile.absolutePath
        // Treat as asset key. Cache key is a hash of the path so different
        // models get different cache files.
        val cacheFile = File(ctx.cacheDir, "wakeword_model_${requested.hashCode()}.tflite")
        if (cacheFile.exists() && cacheFile.length() > 0) return cacheFile.absolutePath
        return try {
            val assetPath = if (requested.startsWith("flutter_assets/")) requested else "flutter_assets/$requested"
            ctx.assets.open(assetPath).use { input ->
                cacheFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to load model from assets: $requested", t)
            null
        }
    }

    private fun bindServiceIfNeeded() {
        val ctx = context ?: return
        if (bound) return
        try {
            val intent = Intent(ctx, WakeWordService::class.java)
            ctx.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to bind service", t)
        }
    }

    private fun teardown() {
        if (bound) {
            try { context?.unbindService(connection) } catch (_: Throwable) {}
            bound = false
        }
        service = null
        ioExecutor.shutdownNow()
    }

    private fun shortsToBytes(samples: ShortArray): ByteArray {
        val out = ByteArray(samples.size * 2)
        for (i in samples.indices) {
            val v = samples[i].toInt()
            out[i * 2] = (v and 0xff).toByte()
            out[i * 2 + 1] = ((v shr 8) and 0xff).toByte()
        }
        return out
    }

    companion object {
        private const val TAG = "WakeWordPlugin"
        const val CHANNEL_CTRL = "igris/wake_word/ctrl"
        const val CHANNEL_EVENT = "igris/wake_word/events"
    }
}
