import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:igris_mobile/main.dart';
import 'package:igris_mobile/models/task_model.dart';
import 'package:igris_mobile/providers/task_provider.dart';
import 'package:igris_mobile/widgets/reminder_dialog.dart';
import 'package:igris_mobile/services/notification_handler_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  ProviderContainer? _container;
  bool _initialized = false;
  final Set<String> _activeDialogTaskIds = {};

  void init(ProviderContainer container) {
    _container = container;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Request permissions for Android 13+
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }

    // Request system alert window permission to display over other apps
    try {
      final status = await Permission.systemAlertWindow.status;
      debugPrint('[ReminderService] System Alert Window permission status: $status');
      if (status.isDenied) {
        debugPrint('[ReminderService] System Alert Window permission is denied, requesting...');
        await Permission.systemAlertWindow.request();
      }
    } catch (e) {
      debugPrint('[ReminderService] Error requesting System Alert Window permission: $e');
    }

    _initialized = true;
    debugPrint('[ReminderService] Notification service initialized');
  }

  // ── Notification Callback ──────────────────────────────────────────────────
  void _onNotificationResponse(NotificationResponse response) async {
    if (response.actionId == 'stop_monitor') {
      debugPrint('[ReminderService] Notification Stop Monitor Action clicked');
      try {
        await NotificationHandlerService().stopService();
      } catch (e) {
        debugPrint('[ReminderService] Error stopping monitor service: $e');
      }
      return;
    }

    if (response.actionId == 'preset_meeting' || response.actionId == 'preset_driving') {
      final isMeeting = response.actionId == 'preset_meeting';
      final statusText = isMeeting ? 'Meeting' : 'Driving';
      final replyText = 'Sanjay is Busy ($statusText)';
      debugPrint('[ReminderService] Notification Preset Status Action clicked: $statusText');
      try {
        final secureStorage = const FlutterSecureStorage();
        await secureStorage.write(key: 'busy_mode_reply', value: replyText);
        
        await NotificationHandlerService().updateMonitorStatus(replyText);
      } catch (e) {
        debugPrint('[ReminderService] Error setting preset status: $e');
      }
      return;
    }

    final payloadStr = response.payload;
    if (payloadStr == null || payloadStr.isEmpty || _container == null) return;

    try {
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;
      final taskId = data['taskId'] as String;

      final tasks = _container!.read(taskProvider);
      final task = tasks.firstWhere((t) => t.id == taskId);

      if (response.actionId == 'complete') {
        debugPrint('[ReminderService] Notification Complete Action clicked for: $taskId');
        await _container!.read(taskProvider.notifier).toggleComplete(taskId);
      } else if (response.actionId == 'snooze') {
        debugPrint('[ReminderService] Notification Snooze Action clicked for: $taskId');
        await _container!.read(taskProvider.notifier).snoozeTask(taskId);
      } else {
        // App opened via notification click — show in-app dialog
        debugPrint('[ReminderService] Notification clicked for: $taskId, showing dialog');
        showReminderDialog(task);
      }
    } catch (e) {
      debugPrint('[ReminderService] Error in notification callback: $e');
    }
  }

  // ── Schedule a Notification ───────────────────────────────────────────────
  Future<void> scheduleReminder(TaskModel task) async {
    if (task.isCompleted) return;

    // Use snoozed time if set, otherwise original due date
    final targetDate = task.snoozedUntil ?? task.dueDate;
    if (targetDate == null) return;

    if (targetDate.isBefore(DateTime.now())) {
      debugPrint('[ReminderService] Cannot schedule reminder in the past for task: ${task.title}');
      return;
    }

    final id = task.id.hashCode;
    final payload = jsonEncode({'taskId': task.id});

    final scheduledTZ = tz.TZDateTime.from(targetDate, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'igris_task_reminders',
      'Task Reminders',
      channelDescription: 'Alerts and snoozes for pending tasks',
      importance: Importance.max,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableVibration: true,
      fullScreenIntent: true,
      actions: [
        const AndroidNotificationAction(
          'complete',
          'Complete',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'snooze',
          'Snooze (5m)',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: 'IGRIS Task Reminder',
        body: task.title + (task.description.isNotEmpty ? '\n${task.description}' : ''),
        scheduledDate: scheduledTZ,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      debugPrint('[ReminderService] Scheduled reminder for: ${task.title} at $scheduledTZ');
    } catch (e) {
      debugPrint('[ReminderService] Error scheduling reminder: $e');
    }
  }

  // ── Cancel a Scheduled Notification ────────────────────────────────────────
  Future<void> cancelReminder(String taskId) async {
    try {
      await _plugin.cancel(id: taskId.hashCode);
      debugPrint('[ReminderService] Cancelled reminder for task ID: $taskId');
    } catch (e) {
      debugPrint('[ReminderService] Error cancelling reminder: $e');
    }
  }

  // ── Show In-App Dialog ─────────────────────────────────────────────────────
  void showReminderDialog(TaskModel task) {
    if (_activeDialogTaskIds.contains(task.id)) {
      debugPrint('[ReminderService] Dialog for task ${task.id} is already showing');
      return;
    }

    // Verify task is still pending before showing dialog
    if (_container != null) {
      try {
        final tasks = _container!.read(taskProvider);
        final currentTask = tasks.firstWhere((t) => t.id == task.id);
        if (currentTask.isCompleted) {
          debugPrint('[ReminderService] Task ${task.id} is already completed, skipping dialog');
          return;
        }
        if (currentTask.snoozedUntil != null && currentTask.snoozedUntil!.isAfter(DateTime.now())) {
          debugPrint('[ReminderService] Task ${task.id} is currently snoozed, skipping dialog');
          return;
        }
      } catch (e) {
        debugPrint('[ReminderService] Error checking task state: $e');
      }
    }

    _activeDialogTaskIds.add(task.id);
    _presentDialogWithRetry(task, 0);
  }

  void _presentDialogWithRetry(TaskModel task, int retryCount) {
    final state = navigatorKey.currentState;
    if (state == null) {
      if (retryCount < 20) { // Retry for up to 10 seconds
        debugPrint('[ReminderService] Navigator state not ready (retry $retryCount), retrying in 500ms...');
        Future.delayed(const Duration(milliseconds: 500), () {
          _presentDialogWithRetry(task, retryCount + 1);
        });
      } else {
        debugPrint('[ReminderService] Navigator state failed to become ready after 10s');
        _activeDialogTaskIds.remove(task.id);
      }
      return;
    }

    // Vibrate device
    HapticFeedback.vibrate();

    showDialog(
      context: state.context,
      barrierDismissible: false, // Force them to interact or choose
      builder: (ctx) => ReminderDialog(task: task),
    ).then((_) {
      _activeDialogTaskIds.remove(task.id);
    });
  }
}
