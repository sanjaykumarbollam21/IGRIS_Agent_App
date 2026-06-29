// WakeWordBridge
//
// Dart-side singleton that talks to the native Kotlin WakeWordPlugin via two
// channels:
//
//   - igris/wake_word/ctrl  (MethodChannel) — start, stop, setSensitivity,
//     checkPermissions, etc.
//   - igris/wake_word/events (EventChannel) — detection, status, error
//     events as a broadcast stream.
//
// The bridge is the *only* thing UI code should import. Riverpod's
// wakeWordProvider wraps it; settings screens and VoiceService hand off to
// it through the provider.
//
// Model location:
//   - If the .tflite is bundled in `assets/wake_word/hey_igris.tflite`
//     (registered in pubspec.yaml's flutter.assets), pass
//     "assets/wake_word/hey_igris.tflite" as modelPath. The native side
//     will copy it to a cache file on first use.
//   - If the model is somewhere on the filesystem (downloaded, user-supplied),
//     pass an absolute path. The native side will use it directly.
//
// On detection, the bridge receives a 1.5 s trailing audio clip (base64
// int16 PCM, 16 kHz mono) so callers can hand it to SttFollowupService /
// Vosk / whisper.cpp for the "Hey IGRIS, what's the weather" follow-up.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class WakeWordDetection {
  final double score;
  final double threshold;
  final int capturedAtMs;
  final int sampleRate;
  final Uint8List audioPcm16; // 16 kHz mono int16 PCM
  WakeWordDetection({
    required this.score,
    required this.threshold,
    required this.capturedAtMs,
    required this.sampleRate,
    required this.audioPcm16,
  });
  Duration get capturedAgo =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - capturedAtMs);
}

class WakeWordStatusEvent {
  final String state; // starting | listening | stopping | stopped | error
  final Map<String, Object?> extras;
  WakeWordStatusEvent(this.state, this.extras);
}

class WakeWordError {
  final String code;
  final String message;
  WakeWordError(this.code, this.message);
}

class WakeWordPermissions {
  final bool mic;
  final bool notifications;
  final bool allGranted;
  final bool batteryIgnored;
  WakeWordPermissions({
    required this.mic,
    required this.notifications,
    required this.allGranted,
    required this.batteryIgnored,
  });
}

class WakeWordBridge {
  WakeWordBridge._();
  static final WakeWordBridge instance = WakeWordBridge._();

  static const _ctrl = MethodChannel('igris/wake_word/ctrl');
  static const _events = EventChannel('igris/wake_word/events');

  Stream<WakeWordDetection>? _detectionStream;
  Stream<WakeWordStatusEvent>? _statusStream;
  Stream<WakeWordError>? _errorStream;

  /// Initialise the bridge; safe to call multiple times.
  Future<void> init() async {
    // Touch the channels to force plugin registration. The first call also
    // returns a status snapshot from the native side if the service is
    // already running (e.g. after a process restart).
    try {
      await _ctrl.invokeMethod('version');
    } on MissingPluginException {
      // The plugin is only registered on Android. iOS calls return this.
      rethrow;
    }
  }

  /// Start the listener. Idempotent: a second call with the same config is
  /// a no-op. Returns the resolved model path the native side is using.
  Future<String> start({
    required String modelPath,
    double sensitivity = 0.5,
  }) async {
    final res = await _ctrl.invokeMapMethod<String, dynamic>('start', {
      'modelPath': modelPath,
      'sensitivity': sensitivity,
    });
    return res?['modelPath'] as String? ?? modelPath;
  }

  Future<void> stop() async {
    await _ctrl.invokeMapMethod<String, dynamic>('stop');
  }

  Future<void> setSensitivity(double sensitivity) async {
    await _ctrl.invokeMapMethod<String, dynamic>('setSensitivity', {
      'sensitivity': sensitivity,
    });
  }

  Future<bool> isListening() async {
    final res = await _ctrl.invokeMapMethod<String, dynamic>('isListening');
    return (res?['running'] as bool?) ?? false;
  }

  Future<WakeWordPermissions> checkPermissions() async {
    final res = await _ctrl.invokeMapMethod<String, dynamic>('checkPermissions');
    if (res == null) {
      return WakeWordPermissions(
        mic: false, notifications: false, allGranted: false, batteryIgnored: false,
      );
    }
    return WakeWordPermissions(
      mic: res['mic'] as bool? ?? false,
      notifications: res['notifications'] as bool? ?? false,
      allGranted: res['allGranted'] as bool? ?? false,
      batteryIgnored: res['batteryIgnored'] as bool? ?? false,
    );
  }

  Future<void> requestPermissions() async {
    await _ctrl.invokeMapMethod<String, dynamic>('requestPermissions');
  }

  Future<void> openNotificationSettings() async {
    await _ctrl.invokeMapMethod<String, dynamic>('openNotificationSettings');
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _ctrl.invokeMapMethod<String, dynamic>('requestIgnoreBatteryOptim');
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    final res = await _ctrl.invokeMapMethod<String, dynamic>(
      'isIgnoringBatteryOptimizations',
    );
    return res?['ignored'] as bool? ?? false;
  }

  /// Broadcast stream of "Hey IGRIS" detections. Each event includes a
  /// 1.5 s trailing audio clip ready to be fed to an STT engine.
  Stream<WakeWordDetection> get detectionStream {
    _detectionStream ??= _events
        .receiveBroadcastStream()
        .where((e) => e is Map && e['type'] == 'detection')
        .map<WakeWordDetection>((dynamic raw) {
      final m = raw as Map;
      final b64 = m['audioBase64'] as String? ?? '';
      return WakeWordDetection(
        score: (m['score'] as num?)?.toDouble() ?? 0.0,
        threshold: (m['threshold'] as num?)?.toDouble() ?? 0.0,
        capturedAtMs: (m['capturedAtMs'] as int?) ??
            DateTime.now().millisecondsSinceEpoch,
        sampleRate: (m['sampleRate'] as int?) ?? 16000,
        audioPcm16: base64Decode(b64),
      );
    }).asBroadcastStream();
    return _detectionStream!;
  }

  /// Stream of coarse status transitions. Useful for updating the settings
  /// UI ("Starting…", "Listening", "Stopped"). Throttled to ≤ 1 Hz inside
  /// the native side so it's safe to listen to from any widget.
  Stream<WakeWordStatusEvent> get statusStream {
    _statusStream ??= _events
        .receiveBroadcastStream()
        .where((e) => e is Map && e['type'] == 'status')
        .map<WakeWordStatusEvent>((dynamic raw) {
      final m = raw as Map;
      return WakeWordStatusEvent(
        m['state'] as String? ?? 'unknown',
        Map<String, Object?>.from(m)..remove('type')..remove('state'),
      );
    }).asBroadcastStream();
    return _statusStream!;
  }

  Stream<WakeWordError> get errorStream {
    _errorStream ??= _events
        .receiveBroadcastStream()
        .where((e) => e is Map && e['type'] == 'error')
        .map<WakeWordError>((dynamic raw) {
      final m = raw as Map;
      return WakeWordError(
        m['code'] as String? ?? 'UNKNOWN',
        m['message'] as String? ?? '',
      );
    }).asBroadcastStream();
    return _errorStream!;
  }
}
