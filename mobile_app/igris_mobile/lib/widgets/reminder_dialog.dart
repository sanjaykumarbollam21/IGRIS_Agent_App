import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/models/task_model.dart';
import 'package:igris_mobile/providers/task_provider.dart';
import 'package:intl/intl.dart';

class ReminderDialog extends ConsumerStatefulWidget {
  final TaskModel task;

  const ReminderDialog({super.key, required this.task});

  @override
  ConsumerState<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends ConsumerState<ReminderDialog> {
  Timer? _autoSnoozeTimer;
  int _timeLeft = 60; // 60 seconds countdown
  static const int _totalTime = 60;

  @override
  void initState() {
    super.initState();
    // Repeated quick vibration on mount to get attention
    Future.microtask(() {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
    });

    // Start auto-snooze timer
    _autoSnoozeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_timeLeft > 1) {
          _timeLeft--;
        } else {
          _autoSnooze();
        }
      });
    });
  }

  @override
  void dispose() {
    _autoSnoozeTimer?.cancel();
    super.dispose();
  }

  void _autoSnooze() {
    _autoSnoozeTimer?.cancel();
    ref.read(taskProvider.notifier).snoozeTask(widget.task.id);
    Navigator.pop(context);
    _showToast('Auto-snoozed for 5 minutes');
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final priorityColor = Color(widget.task.priority.colorValue);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // User ignored/dismissed via system Back button
        _autoSnoozeTimer?.cancel();
        ref.read(taskProvider.notifier).snoozeTask(widget.task.id);
        Navigator.pop(context);
        _showToast('Reminding again in 5m');
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: cs.surface,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header icon and title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.alarm_on_rounded,
                      color: priorityColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IGRIS Reminder',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: priorityColor,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          '${widget.task.category.emoji} ${widget.task.category.label}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Task title
              Text(
                widget.task.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),

              // Task description if present
              if (widget.task.description.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.task.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Priority badge and due time
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: priorityColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${widget.task.priority.emoji} ${widget.task.priority.label} Priority',
                      style: TextStyle(
                        fontSize: 11,
                        color: priorityColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.task.dueDate != null
                        ? DateFormat('HH:mm').format(widget.task.dueDate!)
                        : 'Due now',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Countdown / Auto-snooze progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Auto-snoozing in ${_timeLeft}s',
                        style: TextStyle(
                          fontSize: 12,
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${((_timeLeft / _totalTime) * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _timeLeft / _totalTime,
                      backgroundColor: priorityColor.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(priorityColor),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action buttons layout
              Column(
                children: [
                  // Complete button (Primary action)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () {
                        _autoSnoozeTimer?.cancel();
                        ref.read(taskProvider.notifier).toggleComplete(widget.task.id);
                        Navigator.pop(context);
                        _showToast('✓ Task completed!');
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Complete Task'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Row for Snooze and Ignore
                  Row(
                    children: [
                      // Snooze (5m)
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _autoSnoozeTimer?.cancel();
                              ref.read(taskProvider.notifier).snoozeTask(widget.task.id);
                              Navigator.pop(context);
                              _showToast('Snoozed for 5 minutes');
                            },
                            icon: const Icon(Icons.snooze, size: 18),
                            label: const Text('Snooze'),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Ignore / Dismiss
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: TextButton.icon(
                            onPressed: () {
                              _autoSnoozeTimer?.cancel();
                              ref.read(taskProvider.notifier).snoozeTask(widget.task.id);
                              Navigator.pop(context);
                              _showToast('Reminding again in 5m');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                            label: const Text('Ignore', style: TextStyle(color: Colors.grey)),
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
