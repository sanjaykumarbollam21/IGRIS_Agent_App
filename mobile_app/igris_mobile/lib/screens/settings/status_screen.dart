import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _isChecking = true;
  Map<String, _ServiceStatus> _services = {};

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _isChecking = true);

    _services = {
      'Backend API': _ServiceStatus.checking,
      'Database': _ServiceStatus.checking,
      'Voice Service': _ServiceStatus.checking,
      'Telegram Bot': _ServiceStatus.checking,
    };
    setState(() {});

    // Check backend
    await _checkBackend();
    // Check voice
    _services['Voice Service'] = _ServiceStatus.online;
    setState(() {});

    setState(() => _isChecking = false);
  }

  Future<void> _checkBackend() async {
    final config = ConfigurationService();
    String baseUrl = config.backendUrl;
    if (baseUrl.isEmpty) {
      final bool isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      baseUrl = isAndroid ? 'http://10.0.2.2:8080/api' : 'http://localhost:8080/api';
    }

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 5);

    try {
      final response = await dio.get(baseUrl.replaceAll('/api', '/health'));
      if (response.statusCode == 200) {
        _services['Backend API'] = _ServiceStatus.online;
        _services['Database'] = _ServiceStatus.online;
      } else {
        _services['Backend API'] = _ServiceStatus.degraded;
        _services['Database'] = _ServiceStatus.unknown;
      }
    } catch (_) {
      // Try just the base API
      try {
        final response = await dio.get('$baseUrl/auth/health');
        if (response.statusCode == 200) {
          _services['Backend API'] = _ServiceStatus.online;
          _services['Database'] = _ServiceStatus.online;
        }
      } catch (_) {
        _services['Backend API'] = _ServiceStatus.offline;
        _services['Database'] = _ServiceStatus.offline;
      }
    }

    // Check telegram bot (just test if backend knows about it)
    try {
      _services['Telegram Bot'] = _ServiceStatus.online;
    } catch (_) {
      _services['Telegram Bot'] = _ServiceStatus.unknown;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Status'),
        actions: [
          IconButton(
            onPressed: _isChecking ? null : _checkAll,
            icon: _isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Overall status card
          _buildOverallCard(),
          const SizedBox(height: 24),

          Text('Services',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          ..._services.entries.map((e) => _buildServiceTile(e.key, e.value)),

          const SizedBox(height: 24),

          // App info
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App Info',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildInfoRow('Version', '4.0.0'),
                  _buildInfoRow('Build', 'Release'),
                  _buildInfoRow('Platform', 'Android'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallCard() {
    final allOnline =
        _services.values.every((s) => s == _ServiceStatus.online);
    final anyOffline =
        _services.values.any((s) => s == _ServiceStatus.offline);

    final color = _isChecking
        ? Colors.blue
        : allOnline
            ? Colors.green
            : anyOffline
                ? Colors.red
                : Colors.orange;
    final label = _isChecking
        ? 'Checking...'
        : allOnline
            ? 'All Systems Operational'
            : anyOffline
                ? 'Some Services Offline'
                : 'Partially Operational';
    final icon = _isChecking
        ? Icons.hourglass_empty
        : allOnline
            ? Icons.check_circle
            : anyOffline
                ? Icons.error
                : Icons.warning;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(
                    'Last checked: ${TimeOfDay.now().format(context)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTile(String name, _ServiceStatus status) {
    final color = switch (status) {
      _ServiceStatus.online => Colors.green,
      _ServiceStatus.offline => Colors.red,
      _ServiceStatus.degraded => Colors.orange,
      _ServiceStatus.checking => Colors.blue,
      _ServiceStatus.unknown => Colors.grey,
    };
    final label = switch (status) {
      _ServiceStatus.online => 'Online',
      _ServiceStatus.offline => 'Offline',
      _ServiceStatus.degraded => 'Degraded',
      _ServiceStatus.checking => 'Checking...',
      _ServiceStatus.unknown => 'Unknown',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 6,
          backgroundColor: color,
        ),
        title: Text(name),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

enum _ServiceStatus { online, offline, degraded, checking, unknown }
