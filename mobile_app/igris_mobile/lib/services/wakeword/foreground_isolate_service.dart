// lib/services/wakeword/foreground_isolate_service.dart
//
// On Android, "always listening" only survives Doze / app backgrounding
// if the work runs inside a Foreground Service (FGS). The
// `flutter_foreground_task` package wraps the boilerplate.
//
// Why we need a FGS for wake word:
//   • Android 8+: background services are killed within minutes unless
//     they hold a foreground notification.
//   • Android 10+: microphone access REQUIRES a foreground service of
//     type `microphone` (Manifest already declares this — see
//     FOREGROUND_SERVICE_MICROPHONE in AndroidManifest.xml).
//   • Android 14+: the FGS must declare a matching `foregroundServiceType`
//     in the service itself (the plugin handles this).
//
// On iOS, the equivalent is Background Modes → "audio" combined with
// `AVAudioSession` config — see AppDelegate.swift + Info.plist.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'porcupine_service.dart';

/// Top-level entry point for the foreground isolate.
///
/// The Flutter isolate model means the Dart code running inside the FGS
/// is a *separate* isolate from the UI isolate — that's why we use
/// [SendPort] / [ReceivePort] for callbacks.
@pragma('vm:entry-point')
void startForegroundIsolate() {
  // This must be the FIRST call inside the isolate.
  DartPluginRegistrant.ensureInitialized();

  FlutterForegroundTask.setTaskHandler(WakeWordTaskHandler());
}

class WakeWordTaskHandler extends TaskHandler {
  SendPort? _sendPort;
  final PorcupineWakeWordService _engine = PorcupineWakeWordService.instance;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _log('Foreground isolate started at $timestamp');

    // Listen for the wake word; forward detections to the UI isolate.
    _engine.setOnDetect((event) {
      _sendPort?.send('detect:${event.keywordIndex}');
    });
    _engine.setOnError((_) {
      _sendPort?.send('error');
    });
    _engine.setOnMicPermissionMissing(() {
      _sendPort?.send('perm');
    });

    try {
      await _engine.start();
    } catch (e) {
      _log('Engine start failed in FGS: $e');
      _sendPort?.send('error');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No-op; Porcupine is event-driven via flutter_voice_processor.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _log('Foreground isolate destroyed (timeout=$isTimeout)');
    await _engine.stop();
  }

  @override
  void onReceiveData(Object data) {
    if (data is SendPort) {
      _sendPort = data;
    }
  }

  void _log(String msg) {
    FlutterForegroundTask.sendDataToMain({'log': msg});
    if (kDebugMode) {
      // ignore: avoid_print
      print('[FgsWakeWord] $msg');
    }
  }
}

/// Bridges the FGS isolate to the UI isolate.
class ForegroundBridge {
  ForegroundBridge._();
  static final ForegroundBridge instance = ForegroundBridge._();

  ReceivePort? _receivePort;
  final PorcupineWakeWordService _engine = PorcupineWakeWordService.instance;
  void Function(WakeWordDetectionEvent)? onDetect;
  void Function()? onError;
  void Function()? onPermissionMissing;

  /// Initialise the FGS configuration. Must be called once at app startup
  /// (in `main()` after `WidgetsFlutterBinding.ensureInitialized()`).
  static Future<void> initOnce() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'igris_wake_word',
        channelName: 'Always-listening',
        channelDescription:
            'Shown while IGRIS is listening for "Hey IGRIS" in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        playSound: false,
        enableVibration: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Boot the FGS. Must be called AFTER the user has granted RECORD_AUDIO
  /// AND POST_NOTIFICATIONS.
  Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      _log('FGS already running');
      return;
    }

    // Set up the cross-isolate port.
    _receivePort?.close();
    _receivePort = ReceivePort();
    _receivePort!.listen((msg) {
      if (msg is! String) return;
      if (msg.startsWith('detect:')) {
        final idx = int.tryParse(msg.split(':').last) ?? 0;
        onDetect?.call(WakeWordDetectionEvent(idx, DateTime.now()));
      } else if (msg == 'error') {
        onError?.call();
      } else if (msg == 'perm') {
        onPermissionMissing?.call();
      }
    });

    // Init the FGS itself. The notification must be non-dismissible for
    // Android to keep the service alive.
    final result = await FlutterForegroundTask.startService(
      serviceId: 4701,
      notificationTitle: 'IGRIS is listening',
      notificationText: 'Say "Hey IGRIS" to wake the assistant',
      callback: startForegroundIsolate,
      // CRITICAL: Android 14+ requires an explicit type. `microphone` is
      // the right value when the FGS is holding the mic.
      serviceTypes: [ForegroundServiceTypes.microphone],
    );
    _log('FGS start result: $result');
    // Note: cross-isolate port is passed via onReceiveData once the
    // task handler calls back — no saveData needed here.
  }

  Future<void> stop() async {
    await _engine.stop();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    _receivePort?.close();
    _receivePort = null;
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ForegroundBridge] $msg');
    }
  }
}
