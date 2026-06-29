// lib/services/wakeword/porcupine_service.dart
//
// DEPRECATED: This is the legacy Picovoice Porcupine implementation. It
// requires a Picovoice AccessKey (paid licence) and a .ppn model trained
// against that key. The production wake word path is now the native Kotlin
// TFLite engine (see ../wake_word_bridge.dart and the Kotlin files under
// android/app/src/main/kotlin/.../wakeword/). This file is kept temporarily
// so users who have a Picovoice AccessKey can still build; new code should
// not import it.
// On-device wake word engine for "Hey IGRIS" powered by Picovoice Porcupine.
//
// Why Porcupine?
//   • Runs entirely on-device — no audio leaves the device until the user
//     says the wake word (aligns with CLAUDE.md Rule 1 / privacy).
//   • Sub-100ms detection latency, designed for always-listening.
//   • ~10-30 mW on a modern ARM core — far cheaper than cloud STT polling.
//   • Custom wake word "Hey IGRIS" trained on the Picovoice Console.
//
// We use the high-level [PorcupineManager] which bundles audio capture
// (via `flutter_voice_processor`). The lower-level [Porcupine] class would
// require us to feed PCM frames manually — not needed here.
//
// Threat model & secrets handling (per CLAUDE.md Rule 1):
//   • AccessKey is read from --dart-define=PICOVOICE_ACCESS_KEY at build
//     time. It is then copied into flutter_secure_storage on first launch.
//   • The .ppn model file is shipped as a Flutter asset. Models are
//     bound to the AccessKey, so the model itself is not a "secret" but is
//     .gitignore'd to avoid accidental redistribution.
//   • Per CLAUDE.md Rule 9 — all errors are caught, logged locally with
//     a sanitized prefix, and never expose the AccessKey or raw stack
//     traces to the UI layer.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';

import '../../utils/app_config.dart';

/// Categorised failure reasons surfaced from [PorcupineWakeWordService.start].
/// The settings UI reads this and tells the user *what to do* (grant mic,
/// add the .ppn file, paste an AccessKey, etc.) instead of failing silently.
enum WakeWordStartError {
  /// No AccessKey in --dart-define and none in secure storage.
  missingAccessKey,

  /// AccessKey was provided but Picovoice rejected it.
  invalidAccessKey,

  /// The .ppn asset is missing from the bundle.
  missingModel,

  /// User has not granted RECORD_AUDIO (Android) / mic usage (iOS).
  micPermission,

  /// Engine started but reported a generic failure.
  engine,

  /// Caught an unrecognised exception.
  unknown,
}

/// Battery profiles that trade off detection accuracy against CPU/drain.
enum WakeWordProfile {
  /// ~30 mW, least false positives, requires a clear "Hey IGRIS" utterance.
  lowPower,

  /// Balanced default — recommended for most users.
  balanced,

  /// Highest sensitivity — may trigger on TV/radio more often.
  highSensitivity,
}

extension WakeWordProfileX on WakeWordProfile {
  /// Sensitivity 0.0–1.0 mapped to the wake word engine's threshold curve.
  /// Higher = more eager to trigger (more false positives).
  /// The exact curve is applied in the native DetectionThrottler.
  double get sensitivity {
    switch (this) {
      case WakeWordProfile.lowPower:
        return 0.30; // strict — few false positives, may miss quiet speech
      case WakeWordProfile.balanced:
        return 0.50; // default
      case WakeWordProfile.highSensitivity:
        return 0.75;
    }
  }

  /// User-facing label for the settings UI.
  String get label {
    switch (this) {
      case WakeWordProfile.lowPower:
        return 'Battery saver';
      case WakeWordProfile.balanced:
        return 'Balanced';
      case WakeWordProfile.highSensitivity:
        return 'High sensitivity';
    }
  }
}

class WakeWordDetectionEvent {
  final int keywordIndex;
  final DateTime detectedAt;
  const WakeWordDetectionEvent(this.keywordIndex, this.detectedAt);
}

typedef WakeWordCallback = void Function(WakeWordDetectionEvent event);

/// Singleton service — only one microphone stream should ever be open.
class PorcupineWakeWordService {
  PorcupineWakeWordService._();
  static final PorcupineWakeWordService instance = PorcupineWakeWordService._();

  static const _kSecureKeyAccess = 'pv_access_key_v1';
  static const _kPrefsEnabled = 'wake_word_enabled';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  PorcupineManager? _manager;
  bool _running = false;
  bool _initializing = false;

  /// Last failure reason surfaced to the UI / settings screen.
  WakeWordStartError? _lastError;
  WakeWordStartError? get lastError => _lastError;

  WakeWordCallback? _onDetect;
  void Function(PorcupineException)? _onError;
  VoidCallback? _onMicPermissionMissing;

  WakeWordProfile _profile = WakeWordProfile.balanced;
  WakeWordProfile get profile => _profile;

  bool get isRunning => _running;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Wire the detection callback. The callback is invoked on a background
  /// isolate — keep work inside lightweight and non-blocking.
  void setOnDetect(WakeWordCallback cb) => _onDetect = cb;
  void setOnError(void Function(PorcupineException) cb) => _onError = cb;
  void setOnMicPermissionMissing(VoidCallback cb) =>
      _onMicPermissionMissing = cb;

  Future<void> setProfile(WakeWordProfile p) async {
    _profile = p;
    // Sensitivities are baked in at init; if running, restart cleanly.
    if (_running) {
      await stop();
      await start();
    }
  }

  /// True iff the user opted in (persisted in secure storage).
  Future<bool> isEnabled() async {
    final v = await _secure.read(key: _kPrefsEnabled);
    return v == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await _secure.write(
      key: _kPrefsEnabled,
      value: enabled ? 'true' : 'false',
    );
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  /// Begin continuous listening. Idempotent.
  Future<void> start() async {
    if (_running || _initializing) return;
    _initializing = true;
    _lastError = null;
    try {
      // 1. Ensure we have an AccessKey (env at build → secure store → fail)
      final accessKey = await _resolveAccessKey();
      if (accessKey.isEmpty) {
        _lastError = WakeWordStartError.missingAccessKey;
        _log('No Picovoice AccessKey configured — wake word disabled');
        return;
      }

      // 2. Resolve the .ppn model file. We prefer the bundled asset; on
      //    unsupported platforms we abort gracefully.
      final keywordPath = await _resolveKeywordPath();
      if (keywordPath == null) {
        _lastError = WakeWordStartError.missingModel;
        _log('No .ppn model found at expected asset path');
        return;
      }

      // 3. Initialise the high-level PorcupineManager. In porcupine_flutter
      //    v4 the manager owns mic capture (via flutter_voice_processor)
      //    AND the keyword model — we don't have to feed PCM frames.
      _manager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        [keywordPath],
        _onKeywordDetected,
        sensitivities: [_profile.sensitivity],
        errorCallback: _onEngineError,
      );
      _log('PorcupineManager ready — engine started');
      _running = true;
    } on PorcupineException catch (e) {
      _log('PorcupineException: message=${e.message}');
      await _cleanup();
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('permission') || msg.contains('denied')) {
        _lastError = WakeWordStartError.micPermission;
        _onMicPermissionMissing?.call();
      } else if (msg.contains('access key') || msg.contains('invalid key')) {
        _lastError = WakeWordStartError.invalidAccessKey;
        _onError?.call(e);
      } else if (msg.contains('model') || msg.contains('keyword')) {
        _lastError = WakeWordStartError.missingModel;
        _onError?.call(e);
      } else {
        _lastError = WakeWordStartError.engine;
        _onError?.call(e);
      }
    } catch (e, st) {
      _lastError = WakeWordStartError.unknown;
      _log('Unexpected wake-word error: $e\n$st');
      await _cleanup();
    } finally {
      _initializing = false;
    }
  }

  /// Stop listening and release the microphone.
  Future<void> stop() async {
    if (!_running && _manager == null) return;
    _running = false;
    await _cleanup();
    _log('Stopped');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _onKeywordDetected(int keywordIndex) {
    _onDetect?.call(WakeWordDetectionEvent(keywordIndex, DateTime.now()));
  }

  void _onEngineError(PorcupineException e) {
    _log('Engine error callback: message=${e.message}');
    _onError?.call(e);
  }

  Future<void> _cleanup() async {
    try {
      _manager?.delete();
    } catch (e) {
      _log('Manager delete threw: $e');
    }
    _manager = null;
  }

  Future<String> _resolveAccessKey() async {
    // Prefer secure storage — survives app restarts without re-bundling.
    final stored = await _secure.read(key: _kSecureKeyAccess);
    if (stored != null && stored.isNotEmpty) return stored;

    // Fall back to --dart-define. Copy to secure store; we keep the
    // reference for this process but never re-read the constant.
    if (AppConfig.picovoiceAccessKey.isNotEmpty) {
      await _secure.write(
        key: _kSecureKeyAccess,
        value: AppConfig.picovoiceAccessKey,
      );
      return AppConfig.picovoiceAccessKey;
    }
    return '';
  }

  Future<String?> _resolveKeywordPath() async {
    // The asset is shipped with the app; we just verify it exists.
    final assetKey = AppConfig.wakeWordModelPath;
    try {
      // Will throw if the asset is missing.
      await rootBundle.load(assetKey);
      return assetKey;
    } catch (_) {
      _log('Wake-word asset not found: $assetKey');
      return null;
    }
  }

  void _log(String msg) {
    // Sanitize: never include the AccessKey in logs.
    if (kDebugMode) {
      // ignore: avoid_print
      print('[PorcupineWakeWord] $msg');
    }
  }
}
