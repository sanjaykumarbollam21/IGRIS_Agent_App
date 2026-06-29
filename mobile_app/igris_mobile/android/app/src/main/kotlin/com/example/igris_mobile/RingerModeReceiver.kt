package com.example.igris_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.util.Log

class RingerModeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == AudioManager.RINGER_MODE_CHANGED_ACTION) {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val ringerMode = audioManager.ringerMode
            Log.d("RingerModeReceiver", "Ringer mode changed to: $ringerMode")

            // If it is not silent mode (ringerMode != 0), stop the monitor service
            if (ringerMode != AudioManager.RINGER_MODE_SILENT) {
                Log.i("RingerModeReceiver", "Device removed from silent mode. Stopping IGRIS monitor service.")
                try {
                    // Send shutdown intent to the notifications handler service
                    val serviceIntent = Intent().apply {
                        component = android.content.ComponentName(
                            context.packageName,
                            "im.zoe.labs.flutter_notification_listener.NotificationsHandlerService"
                        )
                        action = "SHUTDOWN"
                    }
                    context.startService(serviceIntent)

                    // Cancel persistent notification (ID 999)
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    notificationManager.cancel(999)
                } catch (e: Exception) {
                    Log.e("RingerModeReceiver", "Error stopping service: ${e.message}")
                }
            }
        }
    }
}
