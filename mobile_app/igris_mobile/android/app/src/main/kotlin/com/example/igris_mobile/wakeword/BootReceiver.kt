package com.example.igris_mobile.wakeword

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/**
 * Optional auto-start on boot. Disabled by default — to enable, set the
 * `start_on_boot` boolean in the IGRIS SharedPreferences to `true` (the
 * settings screen exposes this as a toggle).
 *
 * The receiver only fires for [Intent.ACTION_BOOT_COMPLETED] and
 * [Intent.ACTION_MY_PACKAGE_REPLACED]. We delay 30s after boot to let the
 * system settle (CPU contention is brutal in the first 5s after boot).
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                if (!shouldStartOnBoot(context)) return
                Log.i(TAG, "Boot detected — scheduling wake word service start in 30s")
                scheduleStart(context)
            }
        }
    }

    private fun shouldStartOnBoot(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_START_ON_BOOT, false)
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun scheduleStart(context: Context) {
        // We use a Handler-thread delay rather than AlarmManager because we
        // need to start a foreground service, which requires a UI / app
        // context, and we don't want to require the SCHEDULE_EXACT_ALARM
        // permission just for this.
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed({
            try {
                WakeWordService.start(context)
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to start wake word service from boot", t)
            }
        }, 30_000L)
    }

    companion object {
        private const val TAG = "BootReceiver"
        const val PREFS_NAME = "igris_wake_word_prefs"
        const val KEY_START_ON_BOOT = "start_on_boot"
    }
}
