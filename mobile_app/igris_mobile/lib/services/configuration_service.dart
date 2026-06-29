import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConfigurationService {
  static final ConfigurationService _instance = ConfigurationService._internal();
  factory ConfigurationService() => _instance;
  ConfigurationService._internal();

  /// Default backend URL.
  ///
  /// SECURITY: never hardcode a real production IP/host here. This default is
  /// only used as a last-resort fallback when neither:
  ///   - the user has saved a backend URL in secure storage, nor
  ///   - the app was built with `--dart-define=IGRIS_BACKEND_URL=...`
  /// Override at build time, e.g.:
  ///   flutter build apk --dart-define=IGRIS_BACKEND_URL=https://api.igris.ai
  static const String _fallbackBackendUrl =
      String.fromEnvironment('IGRIS_FALLBACK_BACKEND_URL', defaultValue: '');

  String _backendUrl = '';
  bool _isInitialized = false;
  final _secureStorage = const FlutterSecureStorage();

  Future<void> initialize() async {
    if (_isInitialized) return;

    var savedUrl = await _secureStorage.read(key: 'backend_url');
    const envUrl = String.fromEnvironment('IGRIS_BACKEND_URL');

    if (savedUrl != null && savedUrl.isNotEmpty) {
      _backendUrl = savedUrl;
    } else if (envUrl.isNotEmpty) {
      _backendUrl = envUrl;
    } else if (_fallbackBackendUrl.isNotEmpty) {
      _backendUrl = _fallbackBackendUrl;
    } else {
      throw StateError(
        'No backend URL configured. Build with '
        '--dart-define=IGRIS_BACKEND_URL=https://your-host, '
        'or set one in the app settings screen.',
      );
    }

    _isInitialized = true;
  }

  String get backendUrl => _backendUrl;

  Future<void> setBackendUrl(String url) async {
    var finalUrl = url;
    if (!kIsWeb && Platform.isAndroid) {
      if (finalUrl.contains('localhost') || finalUrl.contains('127.0.0.1')) {
        finalUrl = finalUrl.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
      }
    }
    _backendUrl = finalUrl;
    await _secureStorage.write(key: 'backend_url', value: finalUrl);
  }

  Future<void> resetBackendUrl() async {
    _backendUrl = _fallbackBackendUrl;
    await _secureStorage.delete(key: 'backend_url');
  }
}