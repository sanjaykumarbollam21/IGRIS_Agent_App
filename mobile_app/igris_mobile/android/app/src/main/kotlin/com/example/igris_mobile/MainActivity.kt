package com.example.igris_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.telecom.TelecomManager
import android.view.KeyEvent
import android.database.Cursor
import android.net.Uri
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.media.AudioAttributes
import android.telephony.TelephonyManager
import android.os.Bundle
import android.os.Handler
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.igris_mobile.wakeword.WakeWordPlugin

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.igris.intents"
    private var ringerModeReceiver: BroadcastReceiver? = null
    private var phoneStateReceiver: BroadcastReceiver? = null
    private var methodChannel: MethodChannel? = null
    
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var wasRinging = false
    private var pendingNumber: String = ""
    private var pendingMessage: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Force enable the Notification Listener component on startup so it is always visible in Settings
        try {
            im.zoe.labs.flutter_notification_listener.NotificationsHandlerService.enableServiceSettings(this)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Register the native "Hey IGRIS" wake word plugin. It exposes a
        // MethodChannel (control) and an EventChannel (detection events) to
        // Dart. The Dart side wires this to lib/services/wakeword/wake_word_bridge.dart.
        flutterEngine.plugins.add(WakeWordPlugin())

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openCamera" -> {
                        try {
                            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openClock" -> {
                        try {
                            val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openContacts" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, ContactsContract.Contacts.CONTENT_URI)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "launchApp" -> {
                        try {
                            val packageName = call.argument<String>("package")
                            if (packageName != null) {
                                val intent = packageManager.getLaunchIntentForPackage(packageName)
                                if (intent != null) {
                                    startActivity(intent)
                                    result.success(true)
                                } else {
                                    result.error("NOT_FOUND", "App not installed: $packageName", null)
                                }
                            } else {
                                result.error("ERROR", "Package name required", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openAppByName" -> {
                        try {
                            val name = call.argument<String>("name") ?: ""
                            if (name.isNotEmpty()) {
                                val success = launchAppByName(name)
                                result.success(success)
                            } else {
                                result.error("ERROR", "App name required", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "searchContact" -> {
                        try {
                            val name = call.argument<String>("name") ?: ""
                            val contacts = searchContacts(name)
                            result.success(contacts)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "callContact" -> {
                        try {
                            val number = call.argument<String>("number") ?: ""
                            if (number.isNotEmpty()) {
                                val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$number"))
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("ERROR", "Phone number required", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "getRingerMode" -> {
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val ringerMode = audioManager.ringerMode
                            result.success(ringerMode)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "hasPhonePermissions" -> {
                        val hasAnswer = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                        val hasReadState = checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
                        val hasSendSms = checkSelfPermission(android.Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
                        val hasReadContacts = checkSelfPermission(android.Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
                        
                        result.success(hasAnswer && hasReadState && hasSendSms && hasReadContacts)
                    }
                    "requestPhonePermissions" -> {
                        try {
                            val permissions = mutableListOf(
                                android.Manifest.permission.READ_PHONE_STATE,
                                android.Manifest.permission.SEND_SMS,
                                android.Manifest.permission.READ_CONTACTS
                            )
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                permissions.add(android.Manifest.permission.ANSWER_PHONE_CALLS)
                            }
                            requestPermissions(permissions.toTypedArray(), 102)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "acceptCall" -> {
                        try {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                                    telecomManager.acceptRingingCall()
                                    result.success(true)
                                } else {
                                    result.error("PERMISSION_DENIED", "ANSWER_PHONE_CALLS permission not granted", null)
                                }
                            } else {
                                val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_HEADSETHOOK)
                                val eventUp = KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_HEADSETHOOK)
                                
                                val intentDown = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                                    putExtra(Intent.EXTRA_KEY_EVENT, eventDown)
                                }
                                sendOrderedBroadcast(intentDown, null)
                                
                                val intentUp = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                                    putExtra(Intent.EXTRA_KEY_EVENT, eventUp)
                                }
                                sendOrderedBroadcast(intentUp, null)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "endCall" -> {
                        try {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                                if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                                    telecomManager.endCall()
                                    result.success(true)
                                } else {
                                    result.error("PERMISSION_DENIED", "ANSWER_PHONE_CALLS permission not granted", null)
                                }
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "setSpeakerphoneOn" -> {
                        try {
                            val enable = call.argument<Boolean>("enable") ?: false
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            audioManager.isSpeakerphoneOn = enable
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "sendSMS" -> {
                        try {
                            val number = call.argument<String>("number") ?: ""
                            val message = call.argument<String>("message") ?: ""
                            if (number.isNotEmpty() && message.isNotEmpty()) {
                                val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                                    getSystemService(android.telephony.SmsManager::class.java)
                                } else {
                                    @Suppress("DEPRECATION")
                                    android.telephony.SmsManager.getDefault()
                                }
                                smsManager.sendTextMessage(number, null, message, null, null)
                                result.success(true)
                            } else {
                                result.error("ERROR", "Number and message required", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "speakToCall" -> {
                        try {
                            val number = call.argument<String>("number") ?: ""
                            val message = call.argument<String>("message") ?: ""
                            if (number.isNotEmpty() && message.isNotEmpty()) {
                                pendingNumber = number
                                pendingMessage = message
                                Log.d("MainActivity", "Starting speakToCall: number=$number, message=$message")
                                
                                initTTS {
                                    try {
                                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                                        audioManager.isSpeakerphoneOn = true
                                        Log.d("MainActivity", "Speakerphone enabled for speakToCall")
                                    } catch (ex: Exception) {
                                        Log.e("MainActivity", "Failed to enable speakerphone: ${ex.message}")
                                    }

                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                                        val audioAttributes = AudioAttributes.Builder()
                                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                            .build()
                                        tts?.setAudioAttributes(audioAttributes)
                                    }
                                    
                                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                                        override fun onStart(utteranceId: String?) {}
                                        override fun onDone(utteranceId: String?) {
                                            runOnUiThread {
                                                endCallAndSendSMS()
                                            }
                                        }
                                        override fun onError(utteranceId: String?) {
                                            runOnUiThread {
                                                endCallAndSendSMS()
                                            }
                                        }
                                    })
                                    
                                    val params = Bundle()
                                    params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "igris_reply")
                                    tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params, "igris_reply")
                                }
                                result.success(true)
                            } else {
                                result.error("ERROR", "Number and message required", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        registerRingerModeReceiver()
        registerPhoneStateReceiver()
    }

    private fun registerRingerModeReceiver() {
        if (ringerModeReceiver == null) {
            ringerModeReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == AudioManager.RINGER_MODE_CHANGED_ACTION) {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val ringerMode = audioManager.ringerMode
                        runOnUiThread {
                            methodChannel?.invokeMethod("ringerModeChanged", ringerMode)
                        }
                    }
                }
            }
            val filter = IntentFilter(AudioManager.RINGER_MODE_CHANGED_ACTION)
            registerReceiver(ringerModeReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ringerModeReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore
            }
        }
        phoneStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    private fun searchContacts(query: String): List<Map<String, String>> {
        val results = mutableListOf<Map<String, String>>()
        if (query.isEmpty()) return results

        var cleanQuery = query.trim()
        val suffixes = arrayOf(" calling", " (mobile)", " (home)", " (work)", " on mobile")
        for (suffix in suffixes) {
            if (cleanQuery.lowercase().endsWith(suffix)) {
                cleanQuery = cleanQuery.substring(0, cleanQuery.length - suffix.length).trim()
            }
        }
        val prefixes = arrayOf("incoming call from ", "incoming call: ", "incoming call ", "call from ", "calling: ", "call: ")
        for (prefix in prefixes) {
            if (cleanQuery.lowercase().startsWith(prefix)) {
                cleanQuery = cleanQuery.substring(prefix.length).trim()
            }
        }

        if (cleanQuery.isEmpty()) return results

        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf("%$cleanQuery%")

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection, selection, selectionArgs,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )
            cursor?.let {
                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (it.moveToNext() && results.size < 5) {
                    val contactName = if (nameIdx >= 0) it.getString(nameIdx) else ""
                    val contactNum = if (numIdx >= 0) it.getString(numIdx) else ""
                    if (contactNum.isNotEmpty()) {
                        results.add(mapOf("name" to contactName, "number" to contactNum))
                    }
                }
            }
        } finally {
            cursor?.close()
        }
        return results
    }

    private fun initTTS(onReady: () -> Unit) {
        if (tts == null) {
            tts = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    ttsReady = true
                    tts?.language = java.util.Locale.US
                    onReady()
                } else {
                    Log.e("MainActivity", "Failed to initialize TTS native engine")
                }
            }
        } else if (ttsReady) {
            onReady()
        }
    }

    private fun endCallAndSendSMS() {
        Log.d("MainActivity", "Native TTS done speaking. Hanging up call programmatically...")
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
            Log.d("MainActivity", "Speakerphone disabled and audio mode reset to normal")
        } catch (ex: Exception) {
            Log.e("MainActivity", "Failed to reset speakerphone: ${ex.message}")
        }

        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                    telecomManager.endCall()
                    Log.d("MainActivity", "Native call endCall invoked successfully")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to end call: ${e.message}")
        }

        // Wait 1 second after the call ends, then send the background SMS!
        Handler(mainLooper).postDelayed({
            if (pendingNumber.isNotEmpty() && pendingMessage.isNotEmpty()) {
                sendBackgroundSMS(pendingNumber, pendingMessage)
            }
        }, 1000)
    }

    private fun sendBackgroundSMS(number: String, message: String) {
        try {
            Log.d("MainActivity", "Sending background SMS to $number: $message")
            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                getSystemService(android.telephony.SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                android.telephony.SmsManager.getDefault()
            }
            smsManager.sendTextMessage(number, null, message, null, null)
            Log.d("MainActivity", "Silent background SMS sent to $number successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to send background SMS: ${e.message}")
        }
    }

    private fun registerPhoneStateReceiver() {
        if (phoneStateReceiver == null) {
            phoneStateReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == "android.intent.action.PHONE_STATE") {
                        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                        Log.d("MainActivity", "Phone state changed: $state")
                        
                        if (state == TelephonyManager.EXTRA_STATE_RINGING) {
                            wasRinging = true
                        } else if (state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                            wasRinging = false
                        } else if (state == TelephonyManager.EXTRA_STATE_IDLE) {
                            wasRinging = false
                        }
                    }
                }
            }
            val filter = IntentFilter("android.intent.action.PHONE_STATE")
            registerReceiver(phoneStateReceiver, filter)
        }
    }

    private fun triggerNativeSpeech() {
        try {
            val ttsActive = tts?.isSpeaking ?: false
            if (ttsActive) {
                Log.d("MainActivity", "TTS is already speaking, skipping auto-trigger")
                return
            }

            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val number = prefs.getString("flutter.last_caller_number", "") ?: ""
            val reply = prefs.getString("flutter.last_caller_reply", "") ?: ""
            
            if (reply.isNotEmpty()) {
                // Safeguard: Do NOT enable speakerphone or read aloud if in a silent context (meeting/class/sleep)
                val lowerReply = reply.lowercase()
                if (lowerReply.contains("meeting") || lowerReply.contains("class") || lowerReply.contains("sleep")) {
                    Log.d("MainActivity", "Silent context detected (meeting/class/sleep). Skipping speech output.")
                    return
                }

                pendingNumber = number
                pendingMessage = reply
                Log.d("MainActivity", "Triggering native speech: number=$number, message=$reply")
                
                Handler(mainLooper).postDelayed({
                    initTTS {
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            audioManager.isSpeakerphoneOn = true
                            Log.d("MainActivity", "Speakerphone enabled for triggerNativeSpeech")
                        } catch (ex: Exception) {
                            Log.e("MainActivity", "Failed to enable speakerphone: ${ex.message}")
                        }

                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                            val audioAttributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                            tts?.setAudioAttributes(audioAttributes)
                        }
                        
                        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                            override fun onStart(utteranceId: String?) {}
                            override fun onDone(utteranceId: String?) {
                                runOnUiThread {
                                    endCallAndSendSMS()
                                }
                            }
                            override fun onError(utteranceId: String?) {
                                runOnUiThread {
                                    endCallAndSendSMS()
                                }
                            }
                        })
                        
                        val params = Bundle()
                        params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "igris_reply")
                        tts?.speak(reply, TextToSpeech.QUEUE_FLUSH, params, "igris_reply")
                    }
                }, 1200)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to trigger native speech: ${e.message}")
        }
    }

    private fun launchAppByName(appName: String): Boolean {
        try {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfos = pm.queryIntentActivities(intent, 0)
            val targetName = appName.lowercase().trim()

            var matchedPackage: String? = null

            // A. Exact case-insensitive match on app label
            for (info in resolveInfos) {
                val label = info.loadLabel(pm).toString().lowercase().trim()
                if (label == targetName) {
                    matchedPackage = info.activityInfo.packageName
                    break
                }
            }

            // B. Containment match (e.g. "play" in "google play store", or "whatsapp" in "whatsapp business")
            if (matchedPackage == null) {
                for (info in resolveInfos) {
                    val label = info.loadLabel(pm).toString().lowercase().trim()
                    if (label.contains(targetName) || targetName.contains(label)) {
                        matchedPackage = info.activityInfo.packageName
                        break
                    }
                }
            }

            // C. Fallback: package name containment (e.g. "spotify" in "com.spotify.music")
            if (matchedPackage == null) {
                for (info in resolveInfos) {
                    val pkgName = info.activityInfo.packageName.lowercase()
                    if (pkgName.contains(targetName)) {
                        matchedPackage = info.activityInfo.packageName
                        break
                    }
                }
            }

            if (matchedPackage != null) {
                val launchIntent = pm.getLaunchIntentForPackage(matchedPackage)
                if (launchIntent != null) {
                    startActivity(launchIntent)
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to launch app by name: ${e.message}")
        }
        return false
    }
}
