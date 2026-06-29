import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class GmailScreen extends StatefulWidget {
  const GmailScreen({super.key});
  @override
  State<GmailScreen> createState() => _GmailScreenState();
}

class _GmailScreenState extends State<GmailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _dio = Dio();
  bool _loading = true;
  bool _connected = false;
  String? _error;
  List<Map<String, dynamic>> _emails = [];
  String? _aiSummary;
  final _toCtrl = TextEditingController();
  final _subCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  String get _base => '${ConfigurationService().backendUrl}/gmail';

  Future<Options> _auth() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token');
    final geminiKey = await secureStorage.read(key: 'gemini_api_key');
    return Options(headers: {
      'Authorization': 'Bearer ${token ?? ''}',
      if (geminiKey != null && geminiKey.isNotEmpty) 'X-Gemini-API-Key': geminiKey,
    });
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _toCtrl.dispose(); _subCtrl.dispose(); _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await _dio.get('$_base/status', options: await _auth());
      final ok = s.data['connected'] as bool? ?? false;
      if (ok) await _loadEmails();
      setState(() { _connected = ok; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadEmails() async {
    try {
      final r = await _dio.get('$_base/emails',
          queryParameters: {'maxResults': 20}, options: await _auth());
      setState(() {
        _emails = List<Map<String, dynamic>>.from(r.data['emails'] ?? []);
        _aiSummary = r.data['summary'] as String?;
      });
    } catch (e) { _snack('Load failed: $e'); }
  }

  Future<void> _connect() async {
    try {
      final r = await _dio.get('$_base/auth-url', options: await _auth());
      await launchUrl(Uri.parse(r.data['authUrl']), mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(seconds: 3));
      _init();
    } catch (e) { _snack('Connect failed: $e'); }
  }

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty || _subCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      _snack('Fill in all fields'); return;
    }
    setState(() => _sending = true);
    try {
      await _dio.post('$_base/send',
          data: {'to': _toCtrl.text.trim(), 'subject': _subCtrl.text.trim(), 'body': _bodyCtrl.text.trim()},
          options: await _auth());
      _toCtrl.clear(); _subCtrl.clear(); _bodyCtrl.clear();
      _snack('✅ Email sent!');
      _tabs.animateTo(0);
    } catch (e) { _snack('Send failed: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gmail'),
        actions: [
          if (_connected) IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEmails),
          if (_connected) PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [const PopupMenuItem(value: 'd', child: Text('Disconnect'))],
            onSelected: (_) async {
              await _dio.delete('$_base/disconnect', options: await _auth());
              setState(() { _connected = false; _emails = []; });
            },
          ),
        ],
        bottom: _connected ? TabBar(controller: _tabs, tabs: const [
          Tab(icon: Icon(Icons.inbox), text: 'Inbox'),
          Tab(icon: Icon(Icons.send), text: 'Compose'),
        ]) : null,
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? _buildError()
          : !_connected ? _buildConnect(cs)
          : TabBarView(controller: _tabs, children: [_buildInbox(cs), _buildCompose(cs)]),
    );
  }

  Widget _buildConnect(ColorScheme cs) => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.mail_outline, size: 80, color: cs.primary.withValues(alpha: 0.4)),
      const SizedBox(height: 24),
      Text('Connect Gmail', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('Link Gmail so IGRIS can read your inbox and send emails.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _connect, icon: const Icon(Icons.link), label: const Text('Connect Gmail')),
    ])),
  );

  Widget _buildInbox(ColorScheme cs) => Column(children: [
    if (_aiSummary != null) Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.auto_awesome, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(_aiSummary!, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer))),
      ]),
    ),
    Expanded(
      child: _emails.isEmpty
          ? Center(child: Text('Inbox is empty', style: TextStyle(color: cs.onSurfaceVariant)))
          : RefreshIndicator(
              onRefresh: _loadEmails,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: _emails.length,
                itemBuilder: (_, i) => _emailTile(_emails[i], cs),
              ),
            ),
    ),
  ]);

  Widget _emailTile(Map<String, dynamic> e, ColorScheme cs) {
    final unread = e['unread'] as bool? ?? false;
    final from = e['from'] as String? ?? 'U';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: unread ? cs.primary : cs.surfaceContainerHighest,
          child: Text(from.substring(0, 1).toUpperCase(),
              style: TextStyle(color: unread ? cs.onPrimary : cs.onSurface, fontWeight: FontWeight.bold)),
        ),
        title: Text(e['subject'] as String? ?? '(no subject)',
            style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal, fontSize: 14),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(from, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(e['snippet'] as String? ?? '',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        trailing: Text(_fmtDate(e['date'] as String?),
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        isThreeLine: true,
        onTap: () => _showDetail(e),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(controller: ctrl, children: [
            Text(e['subject'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('From: ${e['from'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(_fmtDate(e['date'] as String?), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Divider(height: 20),
            Text(e['body'] as String? ?? e['snippet'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.reply, size: 16),
              label: const Text('Reply'),
              onPressed: () {
                Navigator.pop(context);
                _tabs.animateTo(1);
                _toCtrl.text = e['from'] as String? ?? '';
                _subCtrl.text = 'Re: ${e['subject'] ?? ''}';
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCompose(ColorScheme cs) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          TextField(controller: _toCtrl, decoration: _decor('To', Icons.person_outline), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          TextField(controller: _subCtrl, decoration: _decor('Subject', Icons.title)),
          const SizedBox(height: 12),
          TextField(controller: _bodyCtrl, maxLines: 10, decoration: _decor('Message', Icons.edit_outlined)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_sending ? 'Sending…' : 'Send Email'),
          ),
        ])),
      ),
    ]),
  );

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
    const SizedBox(height: 12),
    Text(_error ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
    const SizedBox(height: 12),
    FilledButton.icon(icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: _init),
  ]));

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) { return iso; }
  }

  InputDecoration _decor(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
