package com.example.igris_mobile.wakeword

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.example.igris_mobile.R

/**
 * Builds and posts the persistent low-priority notification required to keep
 * the wake word listener alive as a foreground service on Android 14+ (where
 * foregroundServiceType="microphone" is mandatory while holding the mic).
 *
 * The notification deliberately:
 *   - uses IMPORTANCE_LOW so it doesn't ping / vibrate / heads-up
 *   - is `setOngoing(true)` so the user can't dismiss it accidentally
 *   - includes a "Stop" action that calls [WakeWordService.stopListening]
 *
 * The channel is created idempotently on every call; Android dedupes by id.
 */
internal object WakeWordNotification {

    const val CHANNEL_ID = "igris_wake_word_native"
    const val CHANNEL_NAME = "Hey IGRIS wake word"
    const val NOTIFICATION_ID = 4242
    const val ACTION_STOP = "com.example.igris_mobile.wakeword.STOP"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Persistent notification that keeps the \"Hey IGRIS\" wake word listener active."
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        mgr.createNotificationChannel(channel)
    }

    fun build(context: Context): Notification {
        ensureChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentPi = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        } ?: PendingIntent.getActivity(
            context,
            0,
            Intent(),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val stopPi = PendingIntent.getService(
            context,
            1,
            Intent(context, WakeWordService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val title = context.getString(R.string.wake_word_notification_title)
        val text = context.getString(R.string.wake_word_notification_text)
        val stopLabel = context.getString(R.string.wake_word_notification_stop)

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(contentPi)
            .addAction(0, stopLabel, stopPi)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    /**
     * Posts the notification and promotes this service to a foreground service
     * with the microphone type. Must be called within 10 seconds of
     * [android.app.Service.startForeground] or the system will ANR the process.
     */
    fun startForeground(context: Context) {
        val service = context as? WakeWordService ?: return
        val notification = build(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: microphone FGS type is mandatory while holding the mic.
            ServiceCompat.startForeground(
                service,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun stopForeground(context: Context) {
        val mgr = ContextCompat.getSystemService(context, NotificationManager::class.java) ?: return
        mgr.cancel(NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (context as? WakeWordService)?.stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            (context as? WakeWordService)?.stopForeground(true)
        }
    }

    private object ServiceCompat {
        fun startForeground(
            service: android.app.Service,
            id: Int,
            notification: Notification,
            foregroundServiceType: Int,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(id, notification, foregroundServiceType)
            } else {
                service.startForeground(id, notification)
            }
        }
    }

    @Suppress("DEPRECATION")
    private val STOP_FOREGROUND_REMOVE = android.app.Service.STOP_FOREGROUND_REMOVE
}
