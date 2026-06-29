package com.example.igris_mobile.wakeword

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings

/**
 * Centralized runtime permission handling. The wake word listener needs
 * three things to be allowed before it can run:
 *
 *   1. RECORD_AUDIO (runtime, Android 6+)
 *   2. POST_NOTIFICATIONS (runtime, Android 13+) — required to show the FGS
 *      notification on Android 14+
 *   3. Battery optimizations excluded (user action) — strongly recommended
 *      for always-listening; we ask the user only after they've enabled the
 *      toggle, not at app start.
 */
internal object PermissionsHelper {

    const val REQ_CODE_PERMISSIONS = 9181
    val REQUIRED = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }.toTypedArray()

    fun hasMic(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

    fun hasAll(context: Context): Boolean = REQUIRED.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    fun requestAll(activity: Activity) {
        ActivityCompat.requestPermissions(activity, REQUIRED, REQ_CODE_PERMISSIONS)
    }

    /**
     * True if the app is whitelisted from Doze/standby battery restrictions.
     * Recommended but not required — the listener works without it, but
     * OEMs (Xiaomi, Huawei, Samsung) can kill the FGS in Doze if not.
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = ContextCompat.getSystemService(context, PowerManager::class.java) ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestIgnoreBatteryOptimizations(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations(activity)) return
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        try { activity.startActivity(intent) } catch (_: Throwable) {}
    }

    /**
     * On Android 14+, microphone-type FGSes require a *visible* notification.
     * If the user has globally blocked notifications for the app, we detect
     * that and tell the caller so the UI can show a "please enable
     * notifications" banner.
     */
    fun notificationsAreBlocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        return !granted
    }

    fun openAppNotificationSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            // For older Androids, this constant is missing — fall back to the
            // generic app details screen.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        try { context.startActivity(intent) } catch (_: Throwable) {}
    }
}
