import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:igris_mobile/services/calendar_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _svc = CalendarService();

  bool _loading = true;
  bool _connected = false;
  String? _error;
  String? _aiSummary;

  List<Map<String, dynamic>> _events = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final connected = await _svc.isConnected();
      if (connected) {
        final data = await _svc.getEvents(days: 30, max: 50);
        setState(() {
          _connected = true;
          _events = List<Map<String, dynamic>>.from(data['events'] ?? []);
          _aiSummary = data['summary'] as String?;
          _loading = false;
        });
      } else {
        setState(() { _connected = false; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Get events for a specific day
  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _events.where((e) {
      try {
        final start = DateTime.parse(e['start'] as String).toLocal();
        return isSameDay(start, day);
      } catch (_) { return false; }
    }).toList();
  }

  Future<void> _connectCalendar() async {
    try {
      final url = await _svc.getAuthUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // After user returns, reload
      await Future.delayed(const Duration(seconds: 3));
      _init();
    } catch (e) {
      _snack('Connect failed: $e');
    }
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "${event['title']}"?'),
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
      await _svc.deleteEvent(event['id']);
      setState(() => _events.remove(event));
      _snack('Event deleted');
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
        title: const Text('Calendar'),
        actions: [
          if (_connected)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _init),
          if (_connected)
            PopupMenuButton(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
              ],
              onSelected: (v) async {
                if (v == 'disconnect') {
                  await _svc.disconnect();
                  setState(() { _connected = false; _events = []; });
                }
              },
            ),
        ],
      ),
      floatingActionButton: _connected
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'nlp_cal',
                  onPressed: _showNlpDialog,
                  tooltip: 'Add event in plain English',
                  child: const Icon(Icons.mic),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'add_cal',
                  onPressed: _showAddDialog,
                  child: const Icon(Icons.add),
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : !_connected
                  ? _buildConnectPrompt(cs)
                  : _buildCalendar(cs),
    );
  }

  Widget _buildConnectPrompt(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month, size: 80,
                  color: cs.primary.withValues(alpha: 0.4)),
              const SizedBox(height: 24),
              Text('Connect Google Calendar',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Link your Google Calendar so IGRIS can read your schedule and help you create events.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _connectCalendar,
                icon: const Icon(Icons.link),
                label: const Text('Connect Google Calendar'),
              ),
            ],
          ),
        ),
      );

  Widget _buildCalendar(ColorScheme cs) {
    final selectedEvents = _eventsForDay(_selectedDay ?? _focusedDay);

    return Column(
      children: [
        // AI Summary banner
        if (_aiSummary != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_aiSummary!,
                      style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
                ),
              ],
            ),
          ),

        // Calendar widget
        TableCalendar<Map<String, dynamic>>(
          firstDay: DateTime.now().subtract(const Duration(days: 60)),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          calendarFormat: _calFormat,
          selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
          eventLoader: _eventsForDay,
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
          onFormatChanged: (f) => setState(() => _calFormat = f),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            markerDecoration: BoxDecoration(
              color: cs.secondary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
            formatButtonDecoration: BoxDecoration(),
            formatButtonTextStyle: TextStyle(fontSize: 12),
          ),
        ),

        const Divider(),

        // Events list for selected day
        Expanded(
          child: selectedEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available, size: 48,
                          color: cs.onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 8),
                      Text('No events on this day',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                  itemCount: selectedEvents.length,
                  itemBuilder: (_, i) => _buildEventTile(selectedEvents[i], cs),
                ),
        ),
      ],
    );
  }

  Widget _buildEventTile(Map<String, dynamic> e, ColorScheme cs) {
    final start = _fmtTime(e['start'] as String?);
    final end = _fmtTime(e['end'] as String?);
    final isAllDay = e['isAllDay'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: _eventColor(e['colorId'] as String?, cs),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(e['title'] ?? 'Untitled',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAllDay ? 'All day' : '$start – $end',
              style: TextStyle(fontSize: 12, color: cs.primary),
            ),
            if (e['location'] != null)
              Text('📍 ${e['location']}',
                  style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e['htmlLink'] != null)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 16),
                onPressed: () =>
                    launchUrl(Uri.parse(e['htmlLink']),
                        mode: LaunchMode.externalApplication),
                tooltip: 'Open in Google Calendar',
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              onPressed: () => _deleteEvent(e),
            ),
          ],
        ),
        isThreeLine: e['location'] != null,
      ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _init,
            ),
          ],
        ),
      );

  // ── NLP Dialog ─────────────────────────────────────────────────────────────
  void _showNlpDialog() {
    final ctrl = TextEditingController();
    bool parsing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) => AlertDialog(
          title: Row(children: [
            Icon(Icons.mic, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Describe your event'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'e.g. "Meeting with Ravi tomorrow at 3pm"',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (parsing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: parsing
                  ? null
                  : () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      sd(() => parsing = true);
                      try {
                        final event = await _svc.parseNaturalLanguage(text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _showConfirmEvent(event);
                      } catch (e) {
                        sd(() => parsing = false);
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

  void _showConfirmEvent(Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Title', event['title'] ?? ''),
            _row('Start', _fmtFull(event['start'] as String?)),
            _row('End', _fmtFull(event['end'] as String?)),
            if (event['location'] != null) _row('Location', event['location']),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final created = await _svc.createEvent(
                  title: event['title'] ?? 'New Event',
                  start: event['start'],
                  end: event['end'],
                  description: event['description'],
                  location: event['location'],
                  isAllDay: event['isAllDay'] as bool? ?? false,
                );
                setState(() => _events.insert(0, created));
                _snack('✅ Event created!');
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

  // ── Manual Add Dialog ──────────────────────────────────────────────────────
  void _showAddDialog() {
    final titleCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime startDt = DateTime.now().add(const Duration(hours: 1));
    DateTime endDt = startDt.add(const Duration(hours: 1));
    bool allDay = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) => AlertDialog(
          title: const Text('New Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: _decor('Title', Icons.title),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locCtrl,
                  decoration: _decor('Location (optional)', Icons.location_on),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: _decor('Description (optional)', Icons.description),
                ),
                SwitchListTile(
                  title: const Text('All day', style: TextStyle(fontSize: 14)),
                  value: allDay,
                  onChanged: (v) => sd(() => allDay = v),
                  contentPadding: EdgeInsets.zero,
                ),
                if (!allDay) ...[
                  _dtTile(ctx, '▶ Start', startDt, (d) => sd(() => startDt = d)),
                  _dtTile(ctx, '⏹ End', endDt, (d) => sd(() => endDt = d)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final created = await _svc.createEvent(
                    title: title,
                    start: startDt.toIso8601String(),
                    end: endDt.toIso8601String(),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    location: locCtrl.text.trim().isEmpty
                        ? null
                        : locCtrl.text.trim(),
                    isAllDay: allDay,
                  );
                  setState(() => _events.insert(0, created));
                  _snack('✅ "${created['title']}" created!');
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _dtTile(BuildContext ctx, String label, DateTime dt,
      void Function(DateTime) onChanged) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text(label, style: const TextStyle(fontSize: 13)),
      title: Text(
        DateFormat('dd MMM yyyy  hh:mm a').format(dt),
        style: const TextStyle(fontSize: 13),
      ),
      onTap: () async {
        final date = await showDatePicker(
          context: ctx,
          initialDate: dt,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null) return;
        if (!ctx.mounted) return;
        final time = await showTimePicker(
          context: ctx,
          initialTime: TimeOfDay.fromDateTime(dt),
        );
        if (time == null) return;
        onChanged(DateTime(
            date.year, date.month, date.day, time.hour, time.minute));
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text('$label:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) { return iso; }
  }

  String _fmtFull(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd MMM, h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) { return iso; }
  }

  Color _eventColor(String? colorId, ColorScheme cs) {
    final colors = {
      '1': Colors.blue,
      '2': Colors.green,
      '3': Colors.purple,
      '4': Colors.red,
      '5': Colors.yellow[700]!,
      '6': Colors.orange,
      '7': Colors.teal,
    };
    return colors[colorId] ?? cs.primary;
  }

  InputDecoration _decor(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      );
}
