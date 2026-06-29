import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:http/http.dart' as http;
import 'package:igris_mobile/services/ai_service.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
class NotificationHandlerService {
  static final NotificationHandlerService _instance = NotificationHandlerService._internal();
  factory NotificationHandlerService() => _instance;
  NotificationHandlerService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final ReceivePort _port = ReceivePort();
  static const String _portName = "igris_notification_listener";
  static const _channel = MethodChannel('com.igris.intents');

  void initialize() async {
    // 1. Initialize the listener with a static callback
    NotificationsListener.initialize(callbackHandle: _callback);
    
    // 2. Setup the isolate port to receive events in the UI
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(_port.sendPort, _portName);
    
    _port.listen((message) {
      if (message is NotificationEvent) {
        _handleNotification(message);
      }
    });

    // Set up the MethodChannel handler to receive native ringer mode changes
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ringerModeChanged') {
        final int ringerMode = call.arguments as int;
        debugPrint('[NotificationHandler] Ringer mode changed broadcast received: $ringerMode');
        await handleRingerModeChange(ringerMode);
      }
    });

    // 3. Start the service if enabled
    final busyEnabled = await _secureStorage.read(key: 'busy_mode_enabled') == 'true';
    if (busyEnabled) {
      await startService();
    }
  }

  @pragma('vm:entry-point')
  static void _callback(NotificationEvent event) {
    // Pass the event from the background isolate to the main UI isolate
    final SendPort? send = IsolateNameServer.lookupPortByName(_portName);
    if (send != null) {
      send.send(event);
    } else {
      // Main UI isolate is dead, handle in background!
      NotificationHandlerService()._handleNotification(event);
    }
  }

  Future<void> handleRingerModeChange(int ringerMode) async {
    if (ringerMode == 0) {
      // Silent Mode: Automatically enable busy mode
      final busyEnabled = await _secureStorage.read(key: 'busy_mode_enabled') == 'true';
      if (!busyEnabled) {
        debugPrint('[NotificationHandler] Automatically enabling busy mode since device is in Silent Mode');
        await _secureStorage.write(key: 'busy_mode_enabled', value: 'true');
        
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('busy_mode_enabled', true);
          debugPrint('[NotificationHandler] Synced busy_mode_enabled=true to SharedPreferences on ringer silent');
        } catch (e) {
          debugPrint('[NotificationHandler] Failed to sync busy_mode_enabled to SharedPreferences: $e');
        }

        // Sync status with backend
        try {
          final baseUrl = ConfigurationService().backendUrl;
          final token = await _secureStorage.read(key: 'auth_token');
          if (token != null) {
            await http.put(
              Uri.parse('$baseUrl/settings'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'busyModeEnabled': true,
              }),
            ).timeout(const Duration(seconds: 10));
            debugPrint('[NotificationHandler] Automatic enable synced to backend');
          }
        } catch (e) {
          debugPrint('[NotificationHandler] Failed to sync automatic enable to backend: $e');
        }

        final granted = await requestPermissions();
        if (granted) {
          await startService();
        }
      }
    } else {
      // Vibrate or Normal Mode: Automatically disable busy mode
      final busyEnabled = await _secureStorage.read(key: 'busy_mode_enabled') == 'true';
      if (busyEnabled) {
        debugPrint('[NotificationHandler] Automatically disabling busy mode since device is no longer in Silent Mode ($ringerMode)');
        await stopService();
      }
    }
  }

  static const int _monitorNotificationId = 999;
  static const String _monitorChannelId = "igris_monitor_channel";
  static const String _monitorChannelName = "IGRIS Monitor Mode";

  Future<void> _showMonitorNotification({String? status}) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    // Read the current reply text from storage to display in the body
    final currentReply = status ?? await _secureStorage.read(key: 'busy_mode_reply') ?? 'Sanjay is Busy';
    final shortReply = currentReply.length > 35 ? '${currentReply.substring(0, 32)}...' : currentReply;

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      _monitorChannelId,
      _monitorChannelName,
      channelDescription: 'Ongoing notification showing that IGRIS is monitoring notifications',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      actions: const [
        AndroidNotificationAction(
          'stop_monitor',
          'Turn OFF',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'preset_meeting',
          'Meeting',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'preset_driving',
          'Driving',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      await flutterLocalNotificationsPlugin.show(
        id: _monitorNotificationId,
        title: 'IGRIS Monitor Mode Active',
        body: 'Status: $shortReply',
        notificationDetails: platformChannelSpecifics,
      );
      debugPrint('[NotificationHandler] Persistent monitor notification displayed. Status: $shortReply');
    } catch (e) {
      debugPrint('[NotificationHandler] Error showing persistent notification: $e');
    }
  }

  Future<void> updateMonitorStatus(String replyText) async {
    // 1. Update the notification with the new status
    await _showMonitorNotification(status: replyText);
    
    // 2. Sync to the backend
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _secureStorage.read(key: 'auth_token');
      if (token != null) {
        await http.put(
          Uri.parse('$baseUrl/settings'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'busyModeAutoReply': replyText,
          }),
        ).timeout(const Duration(seconds: 10));
        debugPrint('[NotificationHandler] Synced new preset to backend: $replyText');
      }
    } catch (e) {
      debugPrint('[NotificationHandler] Failed to sync preset status to backend: $e');
    }
  }

  Future<void> _cancelMonitorNotification() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    try {
      await flutterLocalNotificationsPlugin.cancel(id: _monitorNotificationId);
      debugPrint('[NotificationHandler] Persistent monitor notification cancelled');
    } catch (e) {
      debugPrint('[NotificationHandler] Error cancelling persistent notification: $e');
    }
  }

  Future<void> startService() async {
    final hasPermission = await NotificationsListener.hasPermission ?? false;
    if (hasPermission) {
      await NotificationsListener.startService(
        foreground: false,
      );
      await _showMonitorNotification();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('busy_mode_enabled', true);
        debugPrint('[NotificationHandler] Synced busy_mode_enabled=true to SharedPreferences on startService');
      } catch (e) {
        debugPrint('[NotificationHandler] Failed to sync busy_mode_enabled to SharedPreferences: $e');
      }

      debugPrint('[NotificationHandler] Background listener service started');
    } else {
      debugPrint('[NotificationHandler] Cannot start listener service - no permission');
    }
  }

  Future<void> stopService() async {
    await NotificationsListener.stopService();
    await _cancelMonitorNotification();
    await _secureStorage.write(key: 'busy_mode_enabled', value: 'false');

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('busy_mode_enabled', false);
      debugPrint('[NotificationHandler] Synced busy_mode_enabled=false to SharedPreferences on stopService');
    } catch (e) {
      debugPrint('[NotificationHandler] Failed to sync busy_mode_enabled to SharedPreferences: $e');
    }

    debugPrint('[NotificationHandler] Background listener service stopped');

    // Sync status with backend
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _secureStorage.read(key: 'auth_token');
      if (token != null) {
        final response = await http.put(
          Uri.parse('$baseUrl/settings'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'busyModeEnabled': false,
          }),
        ).timeout(const Duration(seconds: 10));
        debugPrint('[NotificationHandler] Stop monitor synced to backend: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[NotificationHandler] Failed to sync stop monitor with backend: $e');
    }
  }

  String _cleanCallerName(String title) {
    String name = title.trim();
    
    // Remove common prefixes
    final prefixes = [
      RegExp(r'^incoming call from:\s*', caseSensitive: false),
      RegExp(r'^incoming call from\s*', caseSensitive: false),
      RegExp(r'^incoming call:\s*', caseSensitive: false),
      RegExp(r'^incoming call\s*', caseSensitive: false),
      RegExp(r'^call from:\s*', caseSensitive: false),
      RegExp(r'^call from\s*', caseSensitive: false),
      RegExp(r'^calling:\s*', caseSensitive: false),
      RegExp(r'^call:\s*', caseSensitive: false),
    ];
    
    for (final prefix in prefixes) {
      name = name.replaceFirst(prefix, '').trim();
    }
    
    // Remove common suffixes
    final suffixes = [
      RegExp(r'\s+calling\.{0,3}$', caseSensitive: false),
      RegExp(r'\s+on mobile$', caseSensitive: false),
      RegExp(r'\s+on home$', caseSensitive: false),
      RegExp(r'\s+on work$', caseSensitive: false),
      RegExp(r'\s*\(mobile\)$', caseSensitive: false),
      RegExp(r'\s*\(home\)$', caseSensitive: false),
      RegExp(r'\s*\(work\)$', caseSensitive: false),
    ];
    
    for (final suffix in suffixes) {
      name = name.replaceFirst(suffix, '').trim();
    }
    
    return name;
  }

  Future<bool> _isDuplicateEvent(String packageName, String title) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sanitizedKey = 'last_processed_${packageName}_$title'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastTime = prefs.getInt(sanitizedKey) ?? 0;
      
      if (now - lastTime < 15000) { // 15 seconds throttle
        return true;
      }
      
      await prefs.setInt(sanitizedKey, now);
      return false;
    } catch (e) {
      debugPrint('[NotificationHandler] Error in deduplication check: $e');
      return false;
    }
  }

  Future<void> _handleNotification(NotificationEvent event) async {
    try {
      // 1. Check if Monitor Mode is enabled
      final busyEnabled = await _secureStorage.read(key: 'busy_mode_enabled') == 'true';
      if (!busyEnabled) return;

      // 2. Get current ringer mode on Android
      int ringerMode = 2; // Default to normal
      try {
        ringerMode = await _channel.invokeMethod<int>('getRingerMode') ?? 2;
      } catch (e) {
        debugPrint('[NotificationHandler] Error getting ringer mode: $e');
      }

      // Only Silent Mode (ringerMode == 0) counts as busy. Vibrate (1) and Normal (2) do not.
      if (ringerMode != 0) {
        debugPrint('[NotificationHandler] Ringer mode is not silent ($ringerMode), skipping auto-reply');
        return;
      }

      final packageName = event.packageName ?? '';
      final title = event.title ?? '';
      final message = event.text ?? '';
      
      if (title.isEmpty) return;

      // Check if it's SMS, WhatsApp, or Call
      final isSms = packageName.contains('com.google.android.apps.messaging') || 
                    packageName.contains('com.android.mms');
      final isWhatsApp = packageName.contains('com.whatsapp');
      final isCall = packageName.contains('dialer') || 
                     packageName.contains('phone') || 
                     packageName.contains('telecom') ||
                     packageName.contains('incallui') ||
                     packageName.contains('contacts');

      // For messages, require message text to be non-empty. For calls, the notification title (caller name/number) is sufficient.
      if (!isCall && message.isEmpty) return;

      if (isSms || isWhatsApp || isCall) {
        // Check for duplicate event
        if (await _isDuplicateEvent(packageName, title)) {
          debugPrint('[NotificationHandler] Skipping duplicate event from $packageName ($title)');
          return;
        }

        final platform = isCall ? 'call' : (isSms ? 'sms' : 'whatsapp');
        
        // Fetch saved reply or generate framed sentence
        String replyMessage = await _secureStorage.read(key: 'busy_mode_reply') ?? "";
        
        // Use AI framing if the saved message is default, empty, or a quick preset
        bool useAiFraming = replyMessage.isEmpty || 
                           replyMessage.trim() == "Sanjay is Busy" || 
                           replyMessage.contains("I'm currently busy") ||
                           replyMessage.contains("Meeting") ||
                           replyMessage.contains("Driving") ||
                           replyMessage.contains("Sleeping") ||
                           replyMessage.contains("class");

        if (useAiFraming) {
          try {
            String contextInfo = "Sanjay is currently busy.";
            if (replyMessage.toLowerCase().contains("meeting")) {
              contextInfo = "Sanjay is currently in a meeting.";
            } else if (replyMessage.toLowerCase().contains("driving")) {
              contextInfo = "Sanjay is currently driving.";
            } else if (replyMessage.toLowerCase().contains("sleeping")) {
              contextInfo = "Sanjay is currently sleeping.";
            } else if (replyMessage.toLowerCase().contains("class")) {
              contextInfo = "Sanjay is currently in class.";
            }

            final prompt = "You are IGRIS, the powerful and respectful Shadow Soldier AI assistant of Sir Sanjay. "
                "Sanjay is currently busy because his phone is in Silent Mode. "
                "Specific context: $contextInfo "
                "Please frame a brief, polite, and helpful auto-reply sentence (maximum 2 sentences) to a message or call from $title. "
                "The person reached out via $platform."
                "${isCall ? 'They called Sanjay. State that Sanjay is busy, and he will call them back.' : 'They sent a message. State that Sanjay is busy and will reply soon.'} "
                "Do NOT use quotes in your response. Output ONLY the response text.";
            replyMessage = await AiService().chat(prompt);
            debugPrint('[NotificationHandler] Successfully AI-framed reply: $replyMessage');
          } catch (e) {
            debugPrint('[NotificationHandler] AI reply framing failed, using fallback: $e');
            if (isCall) {
              replyMessage = "Hello, this is IGRIS, Sanjay's AI assistant. Sanjay is currently busy and cannot take your call right now. He has been notified of your call and will get back to you soon.";
            } else {
              replyMessage = "Hello! I am IGRIS, Sanjay's AI assistant. Sanjay is currently busy. I have received your message and notified him. He will reply as soon as possible.";
            }
          }
        }

        debugPrint('[NotificationHandler] Intercepted notification from $packageName ($title): $message');
        debugPrint('[NotificationHandler] Processing $platform auto-reply to: $title');

        bool repliedLocally = false;

        // If it's a Call, handle it by declining the call programmatically and sending an SMS auto-reply
        if (isCall) {
          final prefs = await SharedPreferences.getInstance();
          final rejectCalls = prefs.getBool('busy_mode_reject_calls') ?? false;
          if (!rejectCalls) {
            debugPrint('[NotificationHandler] Reject incoming calls is disabled, skipping call handling');
            return;
          }

          try {
            // First, resolve the phone number to send the follow-up SMS later
            final String cleanedName = _cleanCallerName(title);
            String cleanNumber = cleanedName.replaceAll(RegExp(r'[^0-9+]'), '');
            if (cleanNumber.length < 10) {
              try {
                final List<dynamic>? contacts = await _channel.invokeMethod('searchContact', {'name': cleanedName});
                if (contacts != null && contacts.isNotEmpty) {
                  final firstContact = contacts.first;
                  final resolvedNumber = (firstContact as Map)['number'] as String?;
                  if (resolvedNumber != null && resolvedNumber.isNotEmpty) {
                    cleanNumber = resolvedNumber.replaceAll(RegExp(r'[^0-9+]'), '');
                  }
                }
              } catch (e) {
                debugPrint('[NotificationHandler] Contact lookup failed: $e');
              }
            }

            // Save last caller details into SharedPreferences so the native PhoneStateListener can access them upon manual/auto answer
            try {
              final prefsInstance = await SharedPreferences.getInstance();
              await prefsInstance.setString('last_caller_number', cleanNumber);
              await prefsInstance.setString('last_caller_name', title);
              await prefsInstance.setString('last_caller_reply', replyMessage);
              debugPrint('[NotificationHandler] Persisted caller info in SharedPreferences: number=$cleanNumber');
            } catch (err) {
              debugPrint('[NotificationHandler] SharedPreferences write failed: $err');
            }

            debugPrint('[NotificationHandler] Declining call programmatically and sending auto-reply SMS...');
            try {
              // Silently hang up/decline the call programmatically so it stops ringing and doesn't disturb the user at all
              await _channel.invokeMethod('endCall');
            } catch (e) {
              debugPrint('[NotificationHandler] Failed to programmatically decline/end call: $e');
            }

            // Send standard background auto-reply SMS 1 second later to allow lines to clear
            Future.delayed(const Duration(seconds: 1), () async {
              if (cleanNumber.length >= 10) {
                try {
                  debugPrint('[NotificationHandler] Sending SMS auto-reply to $cleanNumber...');
                  final bool success = await _channel.invokeMethod<bool>('sendSMS', {
                    'number': cleanNumber,
                    'message': replyMessage,
                  }) ?? false;
                  if (success) {
                    debugPrint('[NotificationHandler] SMS auto-reply sent successfully to $cleanNumber via native MethodChannel');
                  } else {
                    throw PlatformException(code: 'FAILED', message: 'Native sendSMS returned false');
                  }
                } catch (e) {
                  debugPrint('[NotificationHandler] Native SMS auto-reply failed: $e. Trying flutter_sms package fallback...');
                  try {
                    await sendSMS(
                      message: replyMessage,
                      recipients: [cleanNumber],
                    );
                    debugPrint('[NotificationHandler] SMS auto-reply sent successfully to $cleanNumber via flutter_sms package');
                  } catch (smsErr) {
                    debugPrint('[NotificationHandler] Fallback package SMS auto-reply failed: $smsErr');
                  }
                }
              } else {
                debugPrint('[NotificationHandler] Resolved number too short ($cleanNumber), skipping SMS auto-reply');
              }
            });
            
            // Mark repliedLocally as true so we don't trigger the duplicate SMS block below
            repliedLocally = true;
          } catch (e) {
            debugPrint('[NotificationHandler] Error in native call decline sequence: $e');
          }
        }

        // 1. Try sending local auto-reply using Android Notification Reply Action (universal, works for messages/apps)
        if (!isCall && event.actions != null) {
          for (final action in event.actions!) {
            if (action.semantic == 1) { // SEMANTIC_ACTION_REPLY
              final inputs = <String, dynamic>{};
              for (final input in action.inputs ?? []) {
                final key = input.resultKey ?? '';
                if (key.isNotEmpty) {
                  inputs[key] = replyMessage;
                }
              }
              try {
                await action.postInputs(inputs);
                repliedLocally = true;
                debugPrint('[NotificationHandler] Posted direct notification reply to $title');
              } catch (e) {
                debugPrint('[NotificationHandler] Direct notification reply failed: $e');
              }
              break;
            }
          }
        }

        // 2. If it's a Call or SMS where direct reply failed, resolve phone number and send fallback SMS
        if (!repliedLocally && (isSms || isCall)) {
          final String cleanedName = _cleanCallerName(title);
          // Clean the title to check if it's a direct phone number
          String cleanNumber = cleanedName.replaceAll(RegExp(r'[^0-9+]'), '');
          
          // If title is not a valid phone number (e.g. contains name like "Mom" or "Alex"), search contacts
          if (cleanNumber.length < 10) {
            try {
              final List<dynamic>? contacts = await _channel.invokeMethod('searchContact', {'name': cleanedName});
              if (contacts != null && contacts.isNotEmpty) {
                final firstContact = contacts.first;
                final resolvedNumber = (firstContact as Map)['number'] as String?;
                if (resolvedNumber != null && resolvedNumber.isNotEmpty) {
                  cleanNumber = resolvedNumber.replaceAll(RegExp(r'[^0-9+]'), '');
                  debugPrint('[NotificationHandler] Resolved contact $cleanedName to number $cleanNumber');
                }
              }
            } catch (e) {
              debugPrint('[NotificationHandler] Contact lookup failed: $e');
            }
          }

          if (cleanNumber.length >= 10) {
            try {
              debugPrint('[NotificationHandler] Sending silent background SMS to $cleanNumber...');
              final bool success = await _channel.invokeMethod<bool>('sendSMS', {
                'number': cleanNumber,
                'message': replyMessage,
              }) ?? false;
              
              if (success) {
                repliedLocally = true;
                debugPrint('[NotificationHandler] Background SMS sent successfully to $cleanNumber');
              } else {
                debugPrint('[NotificationHandler] Native background SMS returned false');
              }
            } catch (e) {
              debugPrint('[NotificationHandler] Native background SMS failed: $e');
              
              // Fallback to flutter_sms package just in case
              try {
                await sendSMS(
                  message: replyMessage,
                  recipients: [cleanNumber],
                );
                repliedLocally = true;
                debugPrint('[NotificationHandler] Fallback package SMS sent to $cleanNumber');
              } catch (smsErr) {
                debugPrint('[NotificationHandler] Fallback package SMS failed: $smsErr');
              }
            }
          } else {
            debugPrint('[NotificationHandler] Could not resolve valid phone number for $title, fallback SMS skipped');
          }
        }

        // 3. Forward to backend to log message and trigger Telegram alerts
        try {
          final baseUrl = ConfigurationService().backendUrl;
          final token = await _secureStorage.read(key: 'auth_token');
          if (token != null) {
            final response = await http.post(
              Uri.parse('$baseUrl/settings/busy-mode/incoming'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'sender': title,
                'message': message,
                'platform': platform,
              }),
            ).timeout(const Duration(seconds: 10));
            debugPrint('[NotificationHandler] Missed message/call forwarded to backend. Status: ${response.statusCode}');
          } else {
            debugPrint('[NotificationHandler] Auth token unavailable, backend sync skipped');
          }
        } catch (e) {
          debugPrint('[NotificationHandler] Backend sync failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[NotificationHandler] Error handling notification event: $e');
    }
  }

  Future<bool> requestPermissions() async {
    // 1. Request notification listener permission
    bool isPermissionGranted = await NotificationsListener.hasPermission ?? false;
    if (!isPermissionGranted) {
      await NotificationsListener.openPermissionSettings();
      // Wait briefly for user return
      await Future.delayed(const Duration(seconds: 2));
      isPermissionGranted = await NotificationsListener.hasPermission ?? false;
    }

    // 2. Request phone permissions for auto-answering calls
    try {
      final hasPhone = await _channel.invokeMethod<bool>('hasPhonePermissions') ?? false;
      if (!hasPhone) {
        await _channel.invokeMethod('requestPhonePermissions');
      }
    } catch (e) {
      debugPrint('[NotificationHandler] Error checking/requesting phone permissions: $e');
    }
    
    // Start foreground listener service immediately if permission is granted
    if (isPermissionGranted) {
      await startService();
    }
    return isPermissionGranted;
  }
}
