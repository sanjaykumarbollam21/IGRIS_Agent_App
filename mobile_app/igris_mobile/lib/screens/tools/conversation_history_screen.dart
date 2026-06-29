import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class ConversationHistoryScreen extends StatefulWidget {
  const ConversationHistoryScreen({super.key});
  @override
  State<ConversationHistoryScreen> createState() => _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  final _dio = Dio();
  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];
  String? _error;

  String get _base => '${ConfigurationService().backendUrl}/conversations';

  Future<Options> _auth() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token') ?? '';
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await _dio.get('$_base/sessions', options: await _auth());
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(r.data['sessions'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('Delete this entire conversation? This cannot be undone.'),
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
      await _dio.delete('$_base/sessions/$sessionId', options: await _auth());
      setState(() => _sessions.removeWhere((s) => s['sessionId'] == sessionId));
      _snack('Conversation deleted');
    } catch (e) { _snack('Delete failed: $e'); }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All History'),
        content: const Text('Delete ALL conversation history? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _dio.delete('$_base/all', options: await _auth());
      setState(() => _sessions.clear());
      _snack('All history cleared');
    } catch (e) { _snack('Clear failed: $e'); }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation History'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          if (_sessions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _sessions.isEmpty
                  ? _buildEmpty(cs)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sessions.length,
                        itemBuilder: (_, i) => _sessionCard(_sessions[i], cs),
                      ),
                    ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> s, ColorScheme cs) {
    final sessionId = s['sessionId'] as String? ?? '';
    final count = s['messageCount'] ?? 0;
    final lastAt = _fmtDate(s['lastMessageAt'] as String?);
    final preview = s['firstMessage'] as String? ?? 'Conversation';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.chat_bubble_outline, color: cs.primary, size: 20),
        ),
        title: Text(
          preview.length > 60 ? '${preview.substring(0, 60)}…' : preview,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text('$count messages · $lastAt', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => _openSession(sessionId),
              tooltip: 'View messages',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: () => _deleteSession(sessionId),
            ),
          ],
        ),
        onTap: () => _openSession(sessionId),
      ),
    );
  }

  void _openSession(String sessionId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SessionDetailScreen(sessionId: sessionId)),
    );
  }

  Widget _buildEmpty(ColorScheme cs) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history, size: 72, color: cs.onSurface.withValues(alpha: 0.2)),
      const SizedBox(height: 16),
      Text('No conversations yet', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Start chatting with IGRIS on the Voice or Chat tab', textAlign: TextAlign.center),
    ]),
  );

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
    Text(_error ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
    const SizedBox(height: 12),
    FilledButton.icon(icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: _load),
  ]));

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return iso; }
  }
}

// ── Session Detail ──────────────────────────────────────────────────────────
class _SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  const _SessionDetailScreen({required this.sessionId});
  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  final _dio = Dio();
  bool _loading = true;
  List<Map<String, dynamic>> _messages = [];

  String get _base => '${ConfigurationService().backendUrl}/conversations';

  Future<Options> _auth() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token') ?? '';
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _dio.get('$_base/sessions/${widget.sessionId}', options: await _auth());
      setState(() {
        _messages = List<Map<String, dynamic>>.from(r.data['messages'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('No messages'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final isUser = m['role'] == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: isUser ? cs.primary : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14).copyWith(
                            bottomRight: isUser ? const Radius.circular(4) : null,
                            bottomLeft: !isUser ? const Radius.circular(4) : null,
                          ),
                        ),
                        child: Text(
                          m['content'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isUser ? cs.onPrimary : cs.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
