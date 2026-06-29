import 'package:shared_preferences/shared_preferences.dart';

/// WakeWordService — listens continuously for "Hey IGRIS" in the background.
/// When detected, calls the provided [onWakeWord] callback.
///
/// Uses a poll loop:  listen → detect phrase → cooldown → repeat
/// Does NOT run in a native background service (no workmanager needed for
///
/// DEPRECATED: This is the legacy STT-poll implementation. It is kept
/// temporarily as a fallback / safety net, but the production wake word
/// path is now the native Kotlin engine reachable through
/// [WakeWordBridge]. New code should use the wakeWordProvider /
/// WakeWordActions API; this class will be removed once we're confident
/// the native path is stable across devices.
/// foreground use). To activate while app is in foreground/minimized,
/// keep the app alive with a foreground notification (workmanager handles that
/// separately if desired).
class WakeWordService {
  static final WakeWordService _i = WakeWordService._();
  factory WakeWordService() => _i;
  WakeWordService._();

  /// Load persisted enabled state (always returns false to prevent the legacy poll loop from running)
  Future<bool> isEnabled() async {
    return false;
  }

  /// Persist enabled state
  Future<void> setEnabled(bool val) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('wake_word_enabled', val);
  }

  bool get isRunning => false;

  /// Legacy STT polling loop disabled in favor of native wake word engine.
  Future<void> start() async {}

  void stop() {}
}
