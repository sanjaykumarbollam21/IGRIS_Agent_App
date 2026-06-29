import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:igris_mobile/screens/splash_screen.dart';
import 'package:igris_mobile/providers/app_provider.dart';
import 'package:igris_mobile/services/localization_service.dart';
import 'package:igris_mobile/services/theme_service.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:igris_mobile/services/notification_handler_service.dart';
import 'package:igris_mobile/services/reminder_service.dart';
import 'package:igris_mobile/services/wakeword/foreground_isolate_service.dart';
import 'package:igris_mobile/services/wakeword/wake_word_bridge.dart';
import 'package:igris_mobile/screens/settings/call_summaries_screen.dart';
import 'package:igris_mobile/screens/settings/busy_mode_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Minimal critical path: only the bare minimum needed to boot the app
  await Hive.initFlutter();

  // Start services in the background without blocking the UI
  // We'll use a separate method to handle this so we can track completion
  final container = ProviderContainer();

  // Run non-blocking initializations
  initializeServicesAsync(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const IgrisApp(),
    ),
  );
}

Future<void> initializeServicesAsync(ProviderContainer container) async {
  try {
    // These are critical for basic app functionality but can be run in parallel
    await Future.wait([
      ConfigurationService().initialize(),
      LocalizationService.init(),
      ThemeService.init(),
      ForegroundBridge.initOnce(),
      WakeWordBridge.instance.init().catchError((e) => debugPrint('[main] WakeWordBridge.init skipped: $e')),
    ]);

    // Initialize Notification Handler
    NotificationHandlerService().initialize();

    // Initialize Reminder Service
    ReminderService().init(container);
    await ReminderService().initialize();

    debugPrint('[main] All background services initialized successfully');
  } catch (e) {
    debugPrint('[main] Error during async service initialization: $e');
  }
}

Future<void> initializeServices(ProviderContainer container) async {
  // Deprecated in favor of initializeServicesAsync to prevent boot hang
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class IgrisApp extends ConsumerWidget {
  const IgrisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IGRIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeService.lightTheme,
      darkTheme: ThemeService.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: LocalizationService.supportedLocales,
      localizationsDelegates: LocalizationService.localizationsDelegates,
      routes: {
        '/busy-mode-summaries': (context) => const CallSummariesScreen(),
        '/busy-mode': (context) => const BusyModeScreen(),
      },
      home: const SplashScreen(),
    );
  }
}