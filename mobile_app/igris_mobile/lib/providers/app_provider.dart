import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provider for the app's theme mode
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// Provider for the app's locale
final localeProvider = StateProvider<Locale>((ref) => const Locale('en', 'US'));
