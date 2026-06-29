import 'package:flutter/material.dart';

class LocalizationService {
  LocalizationService._privateConstructor();
  static final LocalizationService _instance =
      LocalizationService._privateConstructor();
  factory LocalizationService() => _instance;

  static Future<void> init() async {
    // In a real implementation, we would load localization files
    // For now, we'll just set up the supported locales
  }

  static const List<Locale> supportedLocales = [
    Locale('en', 'US'), // English
    Locale('es', 'ES'), // Spanish
    Locale('fr', 'FR'), // French
    Locale('de', 'DE'), // German
    Locale('it', 'IT'), // Italian
    Locale('pt', 'PT'), // Portuguese
    Locale('ru', 'RU'), // Russian
    Locale('zh', 'CN'), // Chinese
    Locale('ja', 'JP'), // Japanese
    Locale('ko', 'KR'), // Korean
  ];

  static List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      [
    // Add your localization delegates here
    // For example, if using flutter_localizations:
    // GlobalMaterialLocalizations.delegate,
    // GlobalWidgetsLocalizations.delegate,
    // GlobalCupertinoLocalizations.delegate,
  ];
}