import 'dart:convert';

enum TaskPriority { low, medium, high, urgent }

enum TaskCategory { personal, work, shopping, health, other }

extension TaskPriorityX on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low: return 'Low';
      case TaskPriority.medium: return 'Medium';
      case TaskPriority.high: return 'High';
      case TaskPriority.urgent: return 'Urgent';
    }
  }

  String get emoji {
    switch (this) {
      case TaskPriority.low: return '🟢';
      case TaskPriority.medium: return '🟡';
      case TaskPriority.high: return '🟠';
      case TaskPriority.urgent: return '🔴';
    }
  }

  int get colorValue {
    switch (this) {
      case TaskPriority.low: return 0xFF4CAF50;
      case TaskPriority.medium: return 0xFFFFC107;
      case TaskPriority.high: return 0xFFFF9800;
      case TaskPriority.urgent: return 0xFFF44336;
    }
  }
}

extension TaskCategoryX on TaskCategory {
  String get label {
    switch (this) {
      case TaskCategory.personal: return 'Personal';
      case TaskCategory.work: return 'Work';
      case TaskCategory.shopping: return 'Shopping';
      case TaskCategory.health: return 'Health';
      case TaskCategory.other: return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case TaskCategory.personal: return '👤';
      case TaskCategory.work: return '💼';
      case TaskCategory.shopping: return '🛒';
      case TaskCategory.health: return '🏥';
      case TaskCategory.other: return '📌';
    }
  }
}

class TaskModel {
  final String id;
  final String title;
  final String description;
  final TaskPriority priority;
  final TaskCategory category;
  final DateTime? dueDate;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int snoozeCount;
  final DateTime? snoozedUntil;

  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = TaskPriority.medium,
    this.category = TaskCategory.personal,
    this.dueDate,
    this.isCompleted = false,
    required this.createdAt,
    this.completedAt,
    this.snoozeCount = 0,
    this.snoozedUntil,
  });

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    TaskPriority? priority,
    TaskCategory? category,
    DateTime? dueDate,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    int? snoozeCount,
    DateTime? snoozedUntil,
    bool clearDueDate = false,
    bool clearCompletedAt = false,
    bool clearSnoozedUntil = false,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      snoozeCount: snoozeCount ?? this.snoozeCount,
      snoozedUntil: clearSnoozedUntil ? null : (snoozedUntil ?? this.snoozedUntil),
    );
  }

  bool get isSnoozed {
    if (isCompleted || snoozedUntil == null) return false;
    return snoozedUntil!.isAfter(DateTime.now());
  }

  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    // If snoozed, it is not considered overdue until the snooze time passes
    final targetDate = snoozedUntil ?? dueDate!;
    return targetDate.isBefore(DateTime.now());
  }

  bool get isDueToday {
    final targetDate = snoozedUntil ?? dueDate;
    if (targetDate == null) return false;
    final now = DateTime.now();
    return targetDate.year == now.year &&
        targetDate.month == now.month &&
        targetDate.day == now.day;
  }

  bool get isDueThisWeek {
    final targetDate = snoozedUntil ?? dueDate;
    if (targetDate == null) return false;
    final now = DateTime.now();
    final weekEnd = now.add(const Duration(days: 7));
    return targetDate.isAfter(now) && targetDate.isBefore(weekEnd);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority.index,
        'category': category.index,
        'dueDate': dueDate?.toIso8601String(),
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'snoozeCount': snoozeCount,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
      };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        priority: TaskPriority.values[json['priority'] as int? ?? 1],
        category: TaskCategory.values[json['category'] as int? ?? 0],
        dueDate: json['dueDate'] != null
            ? DateTime.tryParse(json['dueDate'] as String)
            : null,
        isCompleted: json['isCompleted'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'] as String)
            : null,
        snoozeCount: json['snoozeCount'] as int? ?? 0,
        snoozedUntil: json['snoozedUntil'] != null
            ? DateTime.tryParse(json['snoozedUntil'] as String)
            : null,
      );

  static String encodeList(List<TaskModel> tasks) =>
      jsonEncode(tasks.map((t) => t.toJson()).toList());

  static List<TaskModel> decodeList(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => TaskModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
