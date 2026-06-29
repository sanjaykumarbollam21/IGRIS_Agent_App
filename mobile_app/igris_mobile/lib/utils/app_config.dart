/// Build-time configuration loaded via --dart-define flags.
///
/// All values here are PUBLIC in the sense that they are baked into the binary,
/// but the [picovoiceAccessKey] is treated as a SECRET — read it from
/// dart-define, copy to `flutter_secure_storage` on first launch, then
/// overwrite to '' in memory so the literal does not appear in process
/// memory dumps longer than necessary.
class AppConfig {
  AppConfig._();

  /// Backend API base URL (e.g. https://api.igris.app/api)
  static const String backendUrl = String.fromEnvironment(
    'IGRIS_BACKEND_URL',
    defaultValue: 'http://10.0.2.2:8080/api',
  );

  /// Picovoice AccessKey — passed at build time:
  ///   --dart-define=PICOVOICE_ACCESS_KEY=xxxxxxxx
  /// Get yours at https://console.picovoice.ai/
  static const String picovoiceAccessKey = String.fromEnvironment(
    'PICOVOICE_ACCESS_KEY',
    defaultValue: '',
  );

  /// Path (Flutter asset key) of the .ppn model.
  /// Per CLAUDE.md Rule 1 — never embed a hardcoded key in code; the .ppn
  /// is a public model artifact, but we still let ops swap it.
  static const String wakeWordModelPath = String.fromEnvironment(
    'IGRIS_WAKE_WORD_MODEL',
    defaultValue: 'assets/wake_word/Hey-IGRIS_android.ppn',
  );

  /// True when running with the Flutter debug banner / hot-reload.
  /// Use to gate verbose logging.
  static const bool isDebug = bool.fromEnvironment('DEBUG', defaultValue: true);
}
