import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class CallSummariesScreen extends StatefulWidget {
  const CallSummariesScreen({super.key});

  @override
  State<CallSummariesScreen> createState() => _CallSummariesScreenState();
}

class _CallSummariesScreenState extends State<CallSummariesScreen> {
  final _dio = Dio();
  bool _loading = true;
  List<dynamic> _summaries = [];
  String? _error;

  String get _settingsUrl => '${ConfigurationService().backendUrl}/settings';

  Future<Options> _authOptions() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token') ?? '';
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<void> _loadSummaries() async {
    setState(() { _loading = true; _error = null; });
    try {
      final opts = await _authOptions();
      final resp = await _dio.get('$_settingsUrl/busy-mode/summaries', options: opts);
      setState(() {
        _summaries = resp.data['summaries'] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Summaries')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadSummaries, child: const Text('Retry')),
                    ],
                  ),
                )
              : _summaries.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_missed, size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('No call summaries yet.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _summaries.length,
                      itemBuilder: (context, index) {
                        final s = _summaries[index];
                        final data = s['data'] as Map<String, dynamic>? ?? s;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getUrgencyColor(data['urgency']),
                              child: const Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(data['caller_name'] ?? 'Unknown Caller',
                                         style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['reason'] ?? 'No reason provided'),
                                if (data['callback_requested'] == true)
                                  const Text('🔄 Callback requested',
                                      style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: Text(
                              data['urgency']?.toUpperCase() ?? 'LOW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getUrgencyColor(data['urgency'])
                              ),
                            ),
                            onTap: () => _showDetails(context, data),
                          ),
                        );
                      },
                    ),
    );
  }

  Color _getUrgencyColor(String? urgency) {
    switch (urgency?.toLowerCase()) {
      case 'emergency': return Colors.red.shade800;
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      default: return Colors.grey;
    }
  }

  void _showDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['caller_name'] ?? 'Call Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Number: ${data['caller_number']}'),
            const SizedBox(height: 8),
            Text('Reason: ${data['reason']}'),
            const SizedBox(height: 8),
            Text('Urgency: ${data['urgency']}'),
            if (data['notes'] != null) ...[
              const SizedBox(height: 8),
              Text('Notes: ${data['notes']}'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
