import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/models/task_model.dart';
import 'package:igris_mobile/providers/task_provider.dart';
import 'package:intl/intl.dart';

class TaskManagerScreen extends ConsumerStatefulWidget {
  const TaskManagerScreen({super.key});

  @override
  ConsumerState<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends ConsumerState<TaskManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overdue = ref.watch(overdueTasksProvider);
    final today = ref.watch(todayTasksProvider);
    final upcoming = ref.watch(upcomingTasksProvider);
    final done = ref.watch(completedTasksProvider);

    final totalPending = overdue.length + today.length;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Task Manager',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (totalPending > 0)
              Text('$totalPending task${totalPending > 1 ? 's' : ''} pending',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') {
                _confirmClearDone(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear completed')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Today'),
                  if (overdue.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge('${overdue.length}', Colors.red),
                  ] else if (today.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge('${today.length}', cs.primary),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Upcoming'),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge('${upcoming.length}', cs.secondary),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Done'),
                  if (done.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge('${done.length}', Colors.green),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TaskList(
            tasks: [...overdue, ...today],
            emptyIcon: Icons.check_circle_outline,
            emptyMsg: 'No tasks for today 🎉',
            emptySubMsg: 'Add a task with the + button',
          ),
          _TaskList(
            tasks: upcoming,
            emptyIcon: Icons.upcoming_outlined,
            emptyMsg: 'Nothing upcoming',
            emptySubMsg: 'Schedule tasks with a future due date',
          ),
          _TaskList(
            tasks: done,
            emptyIcon: Icons.done_all,
            emptyMsg: 'No completed tasks yet',
            emptySubMsg: 'Complete tasks and they\'ll show here',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  void _confirmClearDone(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear completed tasks?'),
        content: const Text('This will permanently delete all completed tasks.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(taskProvider.notifier).clearCompleted();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showAddEditSheet(BuildContext context, {TaskModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddEditTaskSheet(existing: existing),
    );
  }
}

// ── Task List ────────────────────────────────────────────────────────────────

class _TaskList extends ConsumerWidget {
  final List<TaskModel> tasks;
  final IconData emptyIcon;
  final String emptyMsg;
  final String emptySubMsg;

  const _TaskList({
    required this.tasks,
    required this.emptyIcon,
    required this.emptyMsg,
    required this.emptySubMsg,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(emptyMsg,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(emptySubMsg,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: tasks.length,
      itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
    );
  }
}

// ── Task Tile ────────────────────────────────────────────────────────────────

class _TaskTile extends ConsumerWidget {
  final TaskModel task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final priorityColor = Color(task.priority.colorValue);

    return Dismissible(
      key: ValueKey(task.id),
      background: _swipeBg(
          Colors.green, Icons.check_circle, 'Complete', Alignment.centerLeft),
      secondaryBackground: _swipeBg(
          Colors.red, Icons.delete, 'Delete', Alignment.centerRight),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await ref.read(taskProvider.notifier).toggleComplete(task.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(task.isCompleted
                  ? 'Task moved back to pending'
                  : '✓ Task completed!'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ));
          }
          return false;
        } else {
          return await _confirmDelete(context);
        }
      },
      onDismissed: (_) =>
          ref.read(taskProvider.notifier).deleteTask(task.id),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: task.isOverdue
                ? Colors.red.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEdit(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Priority stripe
                Container(
                  width: 4,
                  height: 56,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                // Checkbox
                GestureDetector(
                  onTap: () =>
                      ref.read(taskProvider.notifier).toggleComplete(task.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: task.isCompleted
                          ? Colors.green
                          : Colors.transparent,
                      border: Border.all(
                        color: task.isCompleted
                            ? Colors.green
                            : cs.outline.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? cs.onSurface.withValues(alpha: 0.45)
                              : cs.onSurface,
                        ),
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          task.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _chip(
                            '${task.category.emoji} ${task.category.label}',
                            cs.surfaceContainerHighest,
                            cs.onSurface.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          _chip(
                            '${task.priority.emoji} ${task.priority.label}',
                            priorityColor.withValues(alpha: 0.1),
                            priorityColor,
                          ),
                          if (task.dueDate != null || task.snoozedUntil != null) ...[
                            const SizedBox(width: 6),
                            _chip(
                              task.isSnoozed
                                  ? '⏰ Snoozed until ${DateFormat('HH:mm').format(task.snoozedUntil!)}'
                                  : task.isOverdue
                                      ? '⚠ Overdue'
                                      : task.isDueToday
                                          ? '📅 Today ${DateFormat('HH:mm').format(task.dueDate!)}'
                                          : DateFormat('MMM d').format(task.dueDate!),
                              task.isSnoozed
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : task.isOverdue
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : cs.surfaceContainerHighest,
                              task.isSnoozed
                                  ? Colors.orange
                                  : task.isOverdue
                                      ? Colors.red
                                      : cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16,
                    color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w500)),
      );

  Widget _swipeBg(Color color, IconData icon, String label, Alignment align) =>
      Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${task.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddEditTaskSheet(existing: task),
    );
  }
}

// ── Add / Edit Sheet ─────────────────────────────────────────────────────────

class _AddEditTaskSheet extends ConsumerStatefulWidget {
  final TaskModel? existing;
  const _AddEditTaskSheet({this.existing});

  @override
  ConsumerState<_AddEditTaskSheet> createState() => _AddEditTaskSheetState();
}

class _AddEditTaskSheetState extends ConsumerState<_AddEditTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late TaskPriority _priority;
  late TaskCategory _category;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _priority = t?.priority ?? TaskPriority.medium;
    _category = t?.category ?? TaskCategory.personal;
    _dueDate = t?.dueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(isEdit ? 'Edit Task' : 'New Task',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Title
              TextFormField(
                controller: _titleCtrl,
                autofocus: !isEdit,
                decoration: InputDecoration(
                  labelText: 'Task title *',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: const Icon(Icons.notes),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Priority
              Text('Priority',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TaskPriority.values.map((p) {
                  final selected = _priority == p;
                  final color = Color(p.colorValue);
                  return ChoiceChip(
                    label: Text('${p.emoji} ${p.label}'),
                    selected: selected,
                    selectedColor: color.withValues(alpha: 0.2),
                    side: BorderSide(
                        color: selected
                            ? color
                            : cs.outlineVariant.withValues(alpha: 0.5)),
                    onSelected: (_) => setState(() => _priority = p),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Category
              Text('Category',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TaskCategory.values.map((c) {
                  final selected = _category == c;
                  return ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Due date
              Text('Due Date',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_dueDate == null
                          ? 'No due date'
                          : DateFormat('MMM d, yyyy – HH:mm')
                              .format(_dueDate!)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (_dueDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear date',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: Icon(isEdit ? Icons.save : Icons.add_task),
                  label: Text(isEdit ? 'Save Changes' : 'Add Task'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              if (isEdit) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete Task',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
    );
    if (!mounted) return;

    setState(() {
      _dueDate = DateTime(
        date.year, date.month, date.day,
        time?.hour ?? 0, time?.minute ?? 0,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(taskProvider.notifier);
    if (widget.existing != null) {
      notifier.updateTask(widget.existing!.copyWith(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        priority: _priority,
        category: _category,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
      ));
    } else {
      notifier.addTask(TaskModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        priority: _priority,
        category: _category,
        dueDate: _dueDate,
        createdAt: DateTime.now(),
      ));
    }

    Navigator.pop(context);
  }

  void _delete() {
    ref.read(taskProvider.notifier).deleteTask(widget.existing!.id);
    Navigator.pop(context);
  }
}
