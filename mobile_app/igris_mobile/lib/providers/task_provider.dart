import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:igris_mobile/models/task_model.dart';
import 'package:igris_mobile/services/reminder_service.dart';
import 'dart:developer' as developer;

const _kTasksKey = 'igris_tasks_v1';

// ── Provider ────────────────────────────────────────────────────────────────

final taskProvider =
    StateNotifierProvider<TaskNotifier, List<TaskModel>>((ref) {
  return TaskNotifier();
});

// Derived providers for filtered views
final todayTasksProvider = Provider<List<TaskModel>>((ref) {
  final tasks = ref.watch(taskProvider);
  return tasks
      .where((t) => !t.isCompleted && (t.isDueToday || t.dueDate == null))
      .toList()
    ..sort(_byPriority);
});

final upcomingTasksProvider = Provider<List<TaskModel>>((ref) {
  final tasks = ref.watch(taskProvider);
  final now = DateTime.now();
  return tasks
      .where((t) =>
          !t.isCompleted &&
          t.dueDate != null &&
          !t.isDueToday &&
          t.dueDate!.isAfter(now))
      .toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
});

final overdueTasksProvider = Provider<List<TaskModel>>((ref) {
  final tasks = ref.watch(taskProvider);
  return tasks.where((t) => t.isOverdue).toList()..sort(_byPriority);
});

final completedTasksProvider = Provider<List<TaskModel>>((ref) {
  final tasks = ref.watch(taskProvider);
  return tasks
      .where((t) => t.isCompleted)
      .toList()
    ..sort((a, b) => (b.completedAt ?? b.createdAt)
        .compareTo(a.completedAt ?? a.createdAt));
});

final pendingTodayCountProvider = Provider<int>((ref) {
  return ref.watch(todayTasksProvider).length +
      ref.watch(overdueTasksProvider).length;
});

// ── Comparator ──────────────────────────────────────────────────────────────

int _byPriority(TaskModel a, TaskModel b) =>
    b.priority.index.compareTo(a.priority.index);

// ── Notifier ────────────────────────────────────────────────────────────────

class TaskNotifier extends StateNotifier<List<TaskModel>> {
  final List<String> _remindedTaskIds = [];
  Timer? _foregroundTimer;

  TaskNotifier() : super([]) {
    _load();
    _startForegroundTimer();
  }

  @override
  void dispose() {
    _foregroundTimer?.cancel();
    super.dispose();
  }

  void _startForegroundTimer() {
    _foregroundTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      final now = DateTime.now();
      for (final task in state) {
        if (task.isCompleted) continue;

        final targetDate = task.snoozedUntil ?? task.dueDate;
        if (targetDate == null) continue;

        // If targetDate is in the past (up to 30 minutes in the past, to avoid triggering very old tasks)
        // and we haven't reminded yet in this app session
        if (targetDate.isBefore(now) &&
            targetDate.isAfter(now.subtract(const Duration(minutes: 30))) &&
            !_remindedTaskIds.contains(task.id)) {
          
          _remindedTaskIds.add(task.id);
          
          // Trigger the in-app popup and vibrate
          ReminderService().showReminderDialog(task);
        }
      }
    });
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTasksKey);
      if (raw != null && raw.isNotEmpty) {
        state = TaskModel.decodeList(raw);
        // Reschedule reminders for all future active tasks to ensure system sync
        for (final task in state) {
          if (!task.isCompleted && (task.dueDate != null || task.snoozedUntil != null)) {
            ReminderService().scheduleReminder(task);
          }
        }
      }
    } catch (e) {
      developer.log('[TaskProvider] Load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTasksKey, TaskModel.encodeList(state));
    } catch (e) {
      developer.log('[TaskProvider] Save error: $e');
    }
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> addTask(TaskModel task) async {
    state = [...state, task];
    await _save();
    if (task.dueDate != null) {
      await ReminderService().scheduleReminder(task);
    }
  }

  Future<void> updateTask(TaskModel updated) async {
    state = state.map((t) => t.id == updated.id ? updated : t).toList();
    await _save();

    if (updated.isCompleted || (updated.dueDate == null && updated.snoozedUntil == null)) {
      await ReminderService().cancelReminder(updated.id);
    } else {
      // Clear reminded ID so it can alert again if due date was updated
      _remindedTaskIds.remove(updated.id);
      await ReminderService().scheduleReminder(updated);
    }
  }

  Future<void> toggleComplete(String id) async {
    state = state.map((t) {
      if (t.id != id) return t;
      final completed = !t.isCompleted;
      return t.copyWith(
        isCompleted: completed,
        completedAt: completed ? DateTime.now() : null,
        clearCompletedAt: !completed,
        clearSnoozedUntil: completed, // clear snooze state on complete
        snoozeCount: completed ? 0 : t.snoozeCount,
      );
    }).toList();
    await _save();

    final task = state.firstWhere((t) => t.id == id);
    if (task.isCompleted) {
      _remindedTaskIds.remove(id);
      await ReminderService().cancelReminder(id);
    } else {
      if (task.dueDate != null || task.snoozedUntil != null) {
        _remindedTaskIds.remove(id);
        await ReminderService().scheduleReminder(task);
      }
    }
  }

  Future<void> snoozeTask(String id, {Duration duration = const Duration(minutes: 5)}) async {
    final now = DateTime.now();
    final snoozeDate = now.add(duration);

    // Remove from in-memory reminded list so the foreground timer can fire again at the snooze time
    _remindedTaskIds.remove(id);

    state = state.map((t) {
      if (t.id != id) return t;
      return t.copyWith(
        snoozeCount: t.snoozeCount + 1,
        snoozedUntil: snoozeDate,
      );
    }).toList();

    await _save();

    final updated = state.firstWhere((t) => t.id == id);
    await ReminderService().scheduleReminder(updated);
  }

  Future<void> deleteTask(String id) async {
    state = state.where((t) => t.id != id).toList();
    await _save();
    _remindedTaskIds.remove(id);
    await ReminderService().cancelReminder(id);
  }

  Future<void> clearCompleted() async {
    final completedIds = state.where((t) => t.isCompleted).map((t) => t.id).toList();
    state = state.where((t) => !t.isCompleted).toList();
    await _save();
    for (final id in completedIds) {
      _remindedTaskIds.remove(id);
      await ReminderService().cancelReminder(id);
    }
  }
}
