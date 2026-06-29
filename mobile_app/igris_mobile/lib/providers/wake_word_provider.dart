// lib/providers/wake_word_provider.dart
//
// Riverpod glue for the on-device wake word. Exposes:
//   • wakeWordEnabledProvider    — bool
//   • wakeWordProfileProvider    — WakeWordProfile
//   • wakeWordStatusProvider     — WakeWordStatus (idle | starting | listening | error | permMissing)
//   • wakeWordActionsProvider    — WakeWordActions (start/stop, setProfile)
//
// The underlying engine is the native Kotlin WakeWordPlugin (see
// android/app/src/main/kotlin/.../wakeword/). The bridge that talks to it
// is WakeWordBridge (see lib/services/wakeword/wake_word_bridge.dart).
//
// The model is a TFLite file produced by openWakeWord's training script
// (see tools/train_wake_word.py). It is bundled with the app at
// `assets/wake_word/hey_igris.tflite`. Override the path with the
// `IGRIS_WAKEWORD_MODEL` env var at build time, or change
// [_defaultModelAsset] below.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/voice_service.dart';
import '../services/wakeword/porcupine_service.dart' show WakeWordProfile, WakeWordProfileX;
import '../services/wakeword/wake_word_bridge.dart';

enum WakeWordStatus { idle, starting, listening, error, permMissing }

class WakeWordActions {
  WakeWordActions(this._ref) {
    // Subscribe to the native event streams once. They are broadcast so
    // multiple listeners are fine.
    _detectionSub = WakeWordBridge.instance.detectionStream.listen(_onDetection);
    _statusSub = WakeWordBridge.instance.statusStream.listen((e) {
      switch (e.state) {
        case 'starting':
          _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.starting;
          break;
        case 'listening':
          _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.listening;
          break;
        case 'stopping':
        case 'stopped':
          _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.idle;
          break;
        case 'error':
          _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.error;
          break;
      }
    });
    _errorSub = WakeWordBridge.instance.errorStream.listen((err) {
      debugPrint('[WakeWord] error ${err.code}: ${err.message}');
      if (err.code == 'PERMISSION_MISSING' || err.code == 'AUDIO_BUSY') {
        _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.permMissing;
      } else {
        _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.error;
      }
    });
  }

  final Ref _ref;
  StreamSubscription<WakeWordDetection>? _detectionSub;
  StreamSubscription<WakeWordStatusEvent>? _statusSub;
  StreamSubscription<WakeWordError>? _errorSub;

  void dispose() {
    _detectionSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
  }

  Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_word_enabled', true);
    _ref.read(wakeWordEnabledProvider.notifier).state = true;
    await start();
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_word_enabled', false);
    _ref.read(wakeWordEnabledProvider.notifier).state = false;
    await stop();
  }

  /// Start the native listener. Persists the enabled state first so a crash
  /// mid-startup still respects the user's preference.
  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_word_enabled', true);
    _ref.read(wakeWordEnabledProvider.notifier).state = true;

    _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.starting;
    try {
      // Check the prerequisites before binding the service. We don't want
      // to start a foreground service the OS will immediately kill.
      final perms = await WakeWordBridge.instance.checkPermissions();
      if (!perms.mic) {
        await WakeWordBridge.instance.requestPermissions();
      }
      final after = await WakeWordBridge.instance.checkPermissions();
      if (!after.mic) {
        _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.permMissing;
        return;
      }
      // Nudge the user once to whitelist battery optimizations; we don't
      // gate on this — the listener works in Doze, just with a higher
      // chance of being killed by aggressive OEMs.
      if (!after.batteryIgnored) {
        await WakeWordBridge.instance.requestIgnoreBatteryOptimizations();
      }

      final profile = _ref.read(wakeWordProfileProvider);
      await WakeWordBridge.instance.start(
        modelPath: _defaultModelAsset,
        sensitivity: profile.sensitivity,
      );
      // The status stream will set the state to listening when the engine
      // is actually live; we don't set it here to avoid a flicker.
    } catch (e) {
      debugPrint('[WakeWordActions] start failed: $e');
      _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.error;
    }
  }

  Future<void> stop() async {
    try {
      await WakeWordBridge.instance.stop();
    } catch (e) {
      debugPrint('[WakeWordActions] stop failed: $e');
    }
    _ref.read(wakeWordStatusProvider.notifier).state = WakeWordStatus.idle;
  }

  Future<void> setProfile(WakeWordProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wake_word_profile', p.index);
    _ref.read(wakeWordProfileProvider.notifier).state = p;
    // Live-update the running engine's threshold so the user doesn't have
    // to stop & start the listener to feel the change.
    if (_ref.read(wakeWordEnabledProvider)) {
      await WakeWordBridge.instance.setSensitivity(p.sensitivity);
    }
  }

  void _onDetection(WakeWordDetection det) {
    debugPrint(
      '[WakeWord] detection: score=${det.score.toStringAsFixed(3)} '
      'threshold=${det.threshold.toStringAsFixed(3)} '
      'audioClip=${det.audioPcm16.length} bytes',
    );
    // Hand off to the existing voice service. It will play a chime, start
    // STT, and feed the result to the AI / intent handler. We invoke the
    // existing entry point instead of duplicating logic.
    try {
      VoiceService().processWakeWordTrigger?.call();
    } catch (e) {
      debugPrint('[WakeWordActions] handoff to VoiceService failed: $e');
    }
  }
}

/// Path the native side loads. We default to the bundled asset; users who
/// want a custom model can override this in their fork.
const String _defaultModelAsset = 'assets/wake_word/hey_igris.tflite';

final wakeWordEnabledProvider = StateProvider<bool>((ref) => false);
final wakeWordProfileProvider =
    StateProvider<WakeWordProfile>((ref) => WakeWordProfile.balanced);
final wakeWordStatusProvider =
    StateProvider<WakeWordStatus>((ref) => WakeWordStatus.idle);

final wakeWordActionsProvider = Provider<WakeWordActions>((ref) {
  final actions = WakeWordActions(ref);
  ref.onDispose(actions.dispose);
  return actions;
});

/// True if the platform supports the native wake word engine. Currently
/// Android only — iOS and desktop return false so UI can hide the toggle.
final wakeWordSupportedProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return Platform.isAndroid;
});
