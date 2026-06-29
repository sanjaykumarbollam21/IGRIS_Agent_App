import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:igris_mobile/services/theme_service.dart';

// Provider for theme mode
final themeModeProvider =
    StateProvider<ThemeMode>((ref) => ThemeMode.system);

// Provider for theme notifier
final themeModeProviderNotifier =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  // ignore: unused_field
  final Ref _ref;

  ThemeModeNotifier(this._ref) : super(ThemeMode.system) {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeStr = prefs.getString('theme_mode');
    if (themeStr != null) {
      switch (themeStr) {
        case 'light':
          state = ThemeMode.light;
          break;
        case 'dark':
          state = ThemeMode.dark;
          break;
        case 'system':
          state = ThemeMode.system;
          break;
        default:
          state = ThemeMode.system;
      }
    }
  }

  Future<void> _saveThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    String themeStr;
    switch (state) {
      case ThemeMode.light:
        themeStr = 'light';
        break;
      case ThemeMode.dark:
        themeStr = 'dark';
        break;
      case ThemeMode.system:
        themeStr = 'system';
        break;
    }
    await prefs.setString('theme_mode', themeStr);
  }

  ThemeMode update(ThemeMode Function(ThemeMode) cb) {
    final newState = cb(state);
    state = newState;
    _saveThemePreference();
    return newState;
  }
}

// Provider for theme service
final themeServiceProvider = Provider<ThemeService>((ref) {
  return ThemeService();
});