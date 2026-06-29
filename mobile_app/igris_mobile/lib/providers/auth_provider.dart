import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/auth_service.dart';

// Provider for authentication state
final authStateProvider = StateProvider<bool>((ref) => false);

// Provider for authentication notifier
final authStateProviderNotifier =
    StateNotifierProvider<AuthStateNotifier, bool>((ref) {
  return AuthStateNotifier(ref);
});

class AuthStateNotifier extends StateNotifier<bool> {
  final Ref _ref;
  final _secureStorage = const FlutterSecureStorage();

  AuthStateNotifier(this._ref) : super(false) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final token = await _secureStorage.read(key: 'auth_token');
    bool isLoggedIn = token != null && token.isNotEmpty;
    if (isLoggedIn) {
      // Try to refresh token on app start to ensure it's valid
      final success = await tryRefreshToken();
      if (!success) {
        // Token is invalid/expired and could not be refreshed. Log out.
        await logout();
        isLoggedIn = false;
      }
    }
    state = isLoggedIn;
  }

  Future<void> login(String email, String password) async {
    try {
      final authService = _ref.read(authServiceProvider);
      final result = await authService.login(email, password);

      if (result['success']) {
        await _secureStorage.write(key: 'auth_token', value: result['token']);
        if (result['refreshToken'] != null) {
          await _secureStorage.write(
              key: 'refresh_token', value: result['refreshToken']);
        }
        await _secureStorage.write(key: 'user_email', value: email);
        state = true;
      } else {
        throw Exception(result['message'] ?? 'Login failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> register(String email, String password, String firstName,
      String lastName) async {
    try {
      final authService = _ref.read(authServiceProvider);
      final result = await authService.register(
          email, password, firstName, lastName);

      if (result['success']) {
        await _secureStorage.write(key: 'auth_token', value: result['token']);
        if (result['refreshToken'] != null) {
          await _secureStorage.write(
              key: 'refresh_token', value: result['refreshToken']);
        }
        await _secureStorage.write(key: 'user_email', value: email);
        state = true;
      } else {
        throw Exception(result['message'] ?? 'Registration failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Try to refresh the auth token using the stored refresh token.
  /// Returns true if refresh succeeded, false if user must re-login.
  Future<bool> tryRefreshToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final authService = _ref.read(authServiceProvider);
      final result = await authService.refreshToken(refreshToken);

      if (result['success']) {
        await _secureStorage.write(key: 'auth_token', value: result['token']);
        if (result['refreshToken'] != null) {
          await _secureStorage.write(
              key: 'refresh_token', value: result['refreshToken']);
        }
        state = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');
    await _secureStorage.delete(key: 'user_email');
    state = false;
  }

  Future<bool> checkAuthStatus() async {
    final token = await _secureStorage.read(key: 'auth_token');
    bool isLoggedIn = token != null && token.isNotEmpty;
    if (isLoggedIn) {
      final success = await tryRefreshToken();
      if (!success) {
        await logout();
        isLoggedIn = false;
      }
    }
    state = isLoggedIn;
    return isLoggedIn;
  }
}

// Provider for auth service
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});
