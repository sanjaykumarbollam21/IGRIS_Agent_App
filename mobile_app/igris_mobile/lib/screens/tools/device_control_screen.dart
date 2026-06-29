import 'package:flutter/material.dart';
import 'package:igris_mobile/services/system_service.dart';
import 'dart:async';

class DeviceControlScreen extends StatefulWidget {
  const DeviceControlScreen({super.key});

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  final _systemService = SystemService();
  Map<String, dynamic>? _deviceInfo;
  bool _isLoading = true;
  bool _isConnected = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final result = await _systemService.getDeviceStatus();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isConnected = result['success'] == true;
        if (_isConnected) _deviceInfo = result;
      });
    }
  }

  Future<void> _sendCommand(String action, String label,
      {Map<String, dynamic>? params, bool confirm = false}) async {
    final isOnline = _deviceInfo?['isOnline'] == true;
    if (!isOnline) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✗ Cannot execute command: Desktop agent is offline'),
        backgroundColor: Colors.amber,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
      return;
    }

    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Confirm: $label'),
          content: Text('Are you sure you want to $label?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    final result = await _systemService.sendCommand(action, params: params);
    if (mounted) {
      final success = result['success'] == true;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? '✓ $label — Done'
            : '✗ ${result['message'] ?? 'Failed'}'),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Control'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() => _isLoading = true);
              _loadStatus();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isConnected
              ? _buildDisconnected()
              : RefreshIndicator(
                  onRefresh: _loadStatus,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildDeviceCard(),
                      const SizedBox(height: 16),
                      _buildStatsCard(),
                      const SizedBox(height: 16),
                      _buildControlSection(
                        'Power',
                        Icons.power_settings_new,
                        Colors.red,
                        [
                          _ctrl('Lock', Icons.lock, Colors.orange,
                              () => _sendCommand('lock', 'Lock Screen')),
                          _ctrl('Sleep', Icons.bedtime, Colors.indigo,
                              () => _sendCommand('sleep', 'Sleep')),
                          _ctrl('Restart', Icons.restart_alt, Colors.amber,
                              () => _sendCommand('restart', 'Restart',
                                  confirm: true)),
                          _ctrl('Shutdown', Icons.power_off, Colors.red,
                              () => _sendCommand('shutdown', 'Shutdown',
                                  confirm: true)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildControlSection(
                        'Volume',
                        Icons.volume_up,
                        Colors.blue,
                        [
                          _ctrl('Vol -', Icons.volume_down, Colors.blue,
                              () => _sendCommand('volume_down', 'Volume Down')),
                          _ctrl('Mute', Icons.volume_off, Colors.grey,
                              () => _sendCommand('volume_mute', 'Mute')),
                          _ctrl('Vol +', Icons.volume_up, Colors.blue,
                              () => _sendCommand('volume_up', 'Volume Up')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildControlSection(
                        'Display',
                        Icons.monitor,
                        Colors.purple,
                        [
                          _ctrl('Dim', Icons.brightness_low, Colors.amber,
                              () => _sendCommand(
                                  'brightness_down', 'Brightness Down')),
                          _ctrl('Screen Off', Icons.desktop_access_disabled,
                              Colors.grey,
                              () => _sendCommand('screen_off', 'Screen Off')),
                          _ctrl('Bright', Icons.brightness_high, Colors.yellow,
                              () => _sendCommand(
                                  'brightness_up', 'Brightness Up')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildControlSection(
                        'Apps & Tools',
                        Icons.apps,
                        Colors.teal,
                        [
                          _ctrl('Explorer', Icons.folder, Colors.amber,
                              () => _sendCommand(
                                  'open_explorer', 'File Explorer')),
                          _ctrl('Task Mgr', Icons.assessment, Colors.green,
                              () => _sendCommand(
                                  'task_manager', 'Task Manager')),
                          _ctrl('Screenshot', Icons.screenshot, Colors.cyan,
                              () => _sendCommand('screenshot', 'Screenshot')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildOpenAppSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDisconnected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.laptop_chromebook,
                size: 80,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 24),
            Text('No Device Connected',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'Make sure IGRIS backend is running on your laptop\nand both devices are on the same network.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadStatus();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard() {
    final device = _deviceInfo?['device'] ?? {};
    final battery = _deviceInfo?['battery'] ?? {};
    final net = _deviceInfo?['network'];
    final isOnline = _deviceInfo?['isOnline'] == true;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isOnline ? Colors.green : Colors.amber).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(Icons.laptop, size: 28, color: isOnline ? Colors.green : Colors.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device['name']?.toString() ?? 'Unknown',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(device['os']?.toString() ?? '',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isOnline ? Colors.green : Colors.amber).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(isOnline ? 'ONLINE' : 'OFFLINE (LAST KNOWN)',
                      style: TextStyle(
                          color: isOnline ? Colors.green : Colors.amber[600],
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: [
                if (battery['hasBattery'] == true)
                  Builder(
                    builder: (context) {
                      final batteryPct = battery['percent'] is num ? (battery['percent'] as num).toInt() : (double.tryParse(battery['percent']?.toString() ?? '')?.toInt() ?? 0);
                      return _infoChip(
                        Icons.battery_std,
                        '$batteryPct%${battery['isCharging'] == true ? ' ⚡' : ''}',
                        batteryPct > 20 ? Colors.green : Colors.red,
                      );
                    }
                  ),
                if (net != null)
                  _infoChip(Icons.wifi, net['ip']?.toString() ?? '',
                      Colors.blue),
                _infoChip(Icons.timer,
                    _formatUptime(device['uptime'] ?? 0), Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final cpu = _deviceInfo?['cpu'] ?? {};
    final mem = _deviceInfo?['memory'] ?? {};

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Resources',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _resourceBar('CPU', cpu['usage'] ?? 0,
                '${cpu['cores'] ?? 0} cores', _usageColor(cpu['usage'] ?? 0)),
            const SizedBox(height: 12),
            _resourceBar(
                'RAM',
                mem['usagePercent'] ?? 0,
                '${mem['used'] ?? 0} / ${mem['total'] ?? 0} GB',
                _usageColor(mem['usagePercent'] ?? 0)),
          ],
        ),
      ),
    );
  }

  Widget _resourceBar(String label, dynamic percent, String detail, Color color) {
    final pct = (percent is num ? percent.toInt() : (double.tryParse(percent.toString())?.toInt() ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('$pct%',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 2),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildControlSection(
      String title, IconData icon, Color color, List<Widget> controls) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: controls,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenAppSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.open_in_new, size: 20, color: Colors.teal),
                const SizedBox(width: 8),
                Text('Open on Laptop',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _appChip('Chrome', Icons.public),
                _appChip('Notepad', Icons.edit_note),
                _appChip('Calculator', Icons.calculate),
                _appChip('VS Code', Icons.code),
                _appChip('Spotify', Icons.music_note),
                _appChip('Discord', Icons.chat_bubble),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl(
      String label, IconData icon, Color color, VoidCallback onTap) {
    final isOnline = _deviceInfo?['isOnline'] == true;
    final displayColor = isOnline ? color : Colors.grey;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isOnline ? 1.0 : 0.4,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: displayColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: displayColor, size: 22),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _appChip(String name, IconData icon) {
    final isOnline = _deviceInfo?['isOnline'] == true;
    return Opacity(
      opacity: isOnline ? 1.0 : 0.4,
      child: ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(name, style: const TextStyle(fontSize: 12)),
        onPressed: () =>
            _sendCommand('open_app', 'Open $name', params: {'appName': name}),
      ),
    );
  }

  Color _usageColor(dynamic percent) {
    final p = percent is num ? percent.toInt() : (double.tryParse(percent.toString())?.toInt() ?? 0);
    if (p < 50) return Colors.green;
    if (p < 80) return Colors.orange;
    return Colors.red;
  }

  String _formatUptime(dynamic seconds) {
    final s = seconds is int
        ? seconds
        : int.tryParse(seconds.toString()) ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
