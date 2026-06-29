import 'package:flutter/material.dart';
import 'package:igris_mobile/services/automation_service.dart';

class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  final _svc = AutomationService();
  List<Map<String, dynamic>> _automations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _svc.listAutomations();
      if (mounted) setState(() { _automations = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(Map<String, dynamic> a) async {
    try {
      final newState = await _svc.toggleAutomation(a['id']);
      setState(() => a['isActive'] = newState);
    } catch (e) {
      _snack('Toggle failed: $e');
    }
  }

  Future<void> _run(Map<String, dynamic> a) async {
    _snack('Running "${a['name']}"…');
    try {
      final result = await _svc.runAutomation(a['id']);
      _snack('✅ ${a['name']}: $result');
    } catch (e) {
      _snack('❌ Run failed: $e');
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Automation'),
        content: Text('Delete "${a['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.deleteAutomation(a['id']);
      setState(() => _automations.remove(a));
      _snack('Deleted "${a['name']}"');
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Natural language FAB
          FloatingActionButton.small(
            heroTag: 'nlp_fab',
            onPressed: _showNlpDialog,
            tooltip: 'Describe automation in plain English',
            child: const Icon(Icons.mic),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add_fab',
            onPressed: _showAddDialog,
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _automations.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _automations.length,
                        itemBuilder: (_, i) => _buildCard(_automations[i], cs),
                      ),
                    ),
    );
  }

  Widget _buildCard(Map<String, dynamic> a, ColorScheme cs) {
    final isActive = a['isActive'] as bool? ?? true;
    final triggerType = a['triggerType'] as String? ?? 'manual';
    final actionType = a['actionType'] as String? ?? '';

    final triggerIcon = _triggerIcon(triggerType);
    final actionColor = _actionColor(actionType, cs);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isActive ? actionColor : cs.surfaceContainerHighest)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(triggerIcon,
                  color: isActive ? actionColor : cs.onSurfaceVariant, size: 22),
            ),
            title: Text(
              a['name'] ?? 'Unnamed',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isActive ? null : cs.onSurfaceVariant,
              ),
            ),
            subtitle: Text(
              _subtitle(a),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            trailing: Switch(
              value: isActive,
              onChanged: (_) => _toggle(a),
              activeThumbColor: actionColor,
            ),
          ),
          // Run count + last run row
          if (a['runCount'] != null || a['lastRunAt'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.history, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Runs: ${a['runCount'] ?? 0}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  if (a['lastRunAt'] != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Last: ${_fmtDate(a['lastRunAt'])}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          // Action row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run Now'),
                  onPressed: isActive ? () => _run(a) : null,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red,
                  onPressed: () => _delete(a),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 72,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No automations yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Tap + to add one, or the mic to describe it in plain English.',
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Could not load automations'),
            Text(_error ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _load,
            ),
          ],
        ),
      );

  // ── NLP Dialog ────────────────────────────────────────────────────────────
  void _showNlpDialog() {
    final ctrl = TextEditingController();
    bool parsing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.mic, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Describe your automation'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText:
                      'e.g. "Every weekday at 9am, send my mom a good morning message on WhatsApp"',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (parsing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Parsing with Gemini AI…', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: parsing
                  ? null
                  : () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      setDState(() => parsing = true);
                      try {
                        final parsed = await _svc.parseNaturalLanguage(text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _showConfirmParsedDialog(parsed);
                      } catch (e) {
                        setDState(() => parsing = false);
                        _snack('Parse failed: $e');
                      }
                    },
              child: const Text('Parse with AI'),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmParsedDialog(Map<String, dynamic> parsed) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Automation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Name', parsed['name'] ?? ''),
            _infoRow('Trigger', '${parsed['triggerType']} — ${parsed['triggerConfig']?['cronExpr'] ?? parsed['triggerConfig']?['event'] ?? ''}'),
            _infoRow('Action', '${parsed['actionType']} — ${parsed['actionConfig']?['message'] ?? parsed['actionConfig']?['prompt'] ?? ''}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final created = await _svc.createAutomation(
                  name: parsed['name'] ?? 'AI Automation',
                  description: parsed['description'],
                  triggerType: parsed['triggerType'] ?? 'manual',
                  triggerConfig: Map<String, dynamic>.from(parsed['triggerConfig'] ?? {}),
                  actionType: parsed['actionType'] ?? 'notify',
                  actionConfig: Map<String, dynamic>.from(parsed['actionConfig'] ?? {}),
                );
                setState(() => _automations.insert(0, created));
                _snack('✅ Automation created!');
              } catch (e) {
                _snack('Create failed: $e');
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  // ── Manual Add Dialog ─────────────────────────────────────────────────────
  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    String triggerType = 'time_based';
    String actionType = 'notify';
    String cronExpr = '0 9 * * 1-5';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('New Automation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: _decor('Name', Icons.label_outline),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: triggerType,
                  decoration: _decor('Trigger', Icons.bolt),
                  items: const [
                    DropdownMenuItem(value: 'time_based', child: Text('Time / Schedule')),
                    DropdownMenuItem(value: 'event_based', child: Text('Event (WiFi, App…)')),
                    DropdownMenuItem(value: 'manual', child: Text('Manual only')),
                  ],
                  onChanged: (v) => setDState(() => triggerType = v!),
                ),
                if (triggerType == 'time_based') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: cronExpr),
                    decoration: _decor('Cron expression', Icons.schedule),
                    onChanged: (v) => cronExpr = v,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Examples: "0 9 * * 1-5" = weekdays 9am\n"0 8 * * *" = every day 8am',
                      style: TextStyle(fontSize: 11,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: actionType,
                  decoration: _decor('Action', Icons.play_arrow),
                  items: const [
                    DropdownMenuItem(value: 'notify', child: Text('Send notification')),
                    DropdownMenuItem(value: 'send_message', child: Text('Send message')),
                    DropdownMenuItem(value: 'run_ai_task', child: Text('Run AI task')),
                    DropdownMenuItem(value: 'set_reminder', child: Text('Set reminder')),
                    DropdownMenuItem(value: 'busy_mode_on', child: Text('Enable Busy Mode')),
                    DropdownMenuItem(value: 'busy_mode_off', child: Text('Disable Busy Mode')),
                  ],
                  onChanged: (v) => setDState(() => actionType = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  maxLines: 2,
                  decoration: _decor(
                    actionType == 'run_ai_task' ? 'AI prompt' : 'Message / note',
                    Icons.text_fields,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);

                final triggerConfig = triggerType == 'time_based'
                    ? {'cronExpr': cronExpr, 'timezone': 'Asia/Kolkata'}
                    : <String, dynamic>{};

                final actionConfig = actionType == 'run_ai_task'
                    ? {'prompt': msgCtrl.text}
                    : {'message': msgCtrl.text};

                try {
                  final created = await _svc.createAutomation(
                    name: name,
                    triggerType: triggerType,
                    triggerConfig: triggerConfig,
                    actionType: actionType,
                    actionConfig: actionConfig,
                  );
                  setState(() => _automations.insert(0, created));
                  _snack('✅ Automation "$name" created!');
                } catch (e) {
                  _snack('Failed: $e');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _subtitle(Map<String, dynamic> a) {
    final tt = a['triggerType'] as String? ?? '';
    final at = a['actionType'] as String? ?? '';
    final tc = a['triggerConfig'] as Map? ?? {};
    final cron = tc['cronExpr'] as String?;
    final triggerLabel = cron != null
        ? 'Schedule: $cron'
        : tt == 'manual'
            ? 'Manual trigger'
            : tt.replaceAll('_', ' ');
    final actionLabel = at.replaceAll('_', ' ');
    return '$triggerLabel → $actionLabel';
  }

  IconData _triggerIcon(String type) {
    switch (type) {
      case 'time_based': return Icons.schedule;
      case 'event_based': return Icons.bolt;
      default: return Icons.touch_app;
    }
  }

  Color _actionColor(String type, ColorScheme cs) {
    switch (type) {
      case 'send_message': return Colors.green;
      case 'run_ai_task': return cs.primary;
      case 'notify': return cs.tertiary;
      case 'busy_mode_on': return Colors.orange;
      case 'busy_mode_off': return Colors.blue;
      default: return cs.secondary;
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }

  InputDecoration _decor(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
