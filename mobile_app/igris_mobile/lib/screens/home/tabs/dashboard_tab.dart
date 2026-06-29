import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/providers/data_providers.dart';
import 'package:igris_mobile/providers/task_provider.dart';
import 'package:igris_mobile/widgets/common/stat_card.dart';
import 'package:igris_mobile/widgets/common/quick_actions.dart';
import 'package:igris_mobile/widgets/common/recent_activity.dart';
import 'package:igris_mobile/screens/ai/image_gen_screen.dart';
import 'package:igris_mobile/screens/ai/web_search_screen.dart';
import 'package:igris_mobile/screens/ai/image_analysis_screen.dart';
import 'package:igris_mobile/screens/tools/maps_screen.dart';
import 'package:igris_mobile/screens/tools/task_manager_screen.dart';
import 'package:igris_mobile/services/system_service.dart';
import 'dart:async';
import 'dart:convert' show json;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DashboardTab extends ConsumerStatefulWidget {
  const DashboardTab({super.key});

  @override
  ConsumerState<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<DashboardTab> {
  final _systemService = SystemService();
  final _secureStorage = const FlutterSecureStorage();
  Map<String, dynamic>? _deviceInfo;
  bool _isDeviceLoading = true;
  bool _isDeviceConnected = false;
  Timer? _deviceRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadLocalDeviceCache().then((_) {
      _loadDeviceStatus();
    });
    _deviceRefreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _loadDeviceStatus());
  }

  @override
  void dispose() {
    _deviceRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalDeviceCache() async {
    try {
      final cachedStr = await _secureStorage.read(key: 'last_known_device_info');
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final decoded = json.decode(cachedStr);
        if (mounted) {
          setState(() {
            _deviceInfo = decoded;
            _isDeviceLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDeviceStatus() async {
    try {
      final result = await _systemService.getDeviceStatus();
      if (mounted) {
        setState(() {
          _isDeviceLoading = false;
          _isDeviceConnected = result['success'] == true;
          if (_isDeviceConnected) {
            _deviceInfo = result;
            _secureStorage.write(
              key: 'last_known_device_info',
              value: json.encode(result),
            );
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isDeviceLoading = false;
          // Retain the cached stats in _deviceInfo instead of clearing it
        });
      }
    }
  }

  Future<void> _sendQuickCommand(String action, String label) async {
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

    final result = await _systemService.sendCommand(action);
    if (mounted) {
      final success = result['success'] == true;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? '✓ Sent: $label' : '✗ Failed to $label'),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(dashboardStatsProvider);
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(dashboardStatsProvider.notifier).refresh();
        await _loadDeviceStatus();
      },
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildGreeting(stats.userName),
          const SizedBox(height: 20),

          // AI activity stats
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: 'Chats Today',
                  value: stats.isLoading ? '...' : '${stats.conversationsToday}',
                  icon: Icons.chat_bubble_outline,
                  color: cs.primary,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: 'Tools Used',
                  value: stats.isLoading ? '...' : '${stats.toolsUsedToday}',
                  icon: Icons.build_outlined,
                  color: cs.secondary,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTaskStatCard(context, cs),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // System Stats Monitoring Card
          _buildSystemStatsCard(cs),
          const SizedBox(height: 24),

          // AI capability cards
          _buildAiBanner(context, cs),
          const SizedBox(height: 24),

          const QuickActions(),
          const SizedBox(height: 24),

          const RecentActivity(),
        ],
      ),
    );
  }

  Widget _buildTaskStatCard(BuildContext context, ColorScheme cs) {
    final count = ref.watch(pendingTodayCountProvider);
    return StatCard(
      title: 'Tasks Due',
      value: '$count',
      icon: Icons.task_alt,
      color: const Color(0xFF009688),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TaskManagerScreen())),
    );
  }

  Widget _buildGreeting(String userName) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$greeting, $userName! 👋',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('What can IGRIS do for you today?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6))),
      ],
    );
  }

  Widget _buildSystemStatsCard(ColorScheme cs) {
    if (_isDeviceLoading && _deviceInfo == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System Resources',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final device = _deviceInfo?['device'] ?? {};
    final cpu = _deviceInfo?['cpu'] ?? {};
    final mem = _deviceInfo?['memory'] ?? {};
    final battery = _deviceInfo?['battery'] ?? {};
    final isOnline = _deviceInfo?['isOnline'] == true;

    final cpuUsage = cpu['usage'] ?? 0;
    final cpuPct = (cpuUsage is num ? cpuUsage.toInt() : (double.tryParse(cpuUsage.toString())?.toInt() ?? 0));
    final memUsage = mem['usagePercent'] ?? 0;
    final memPct = (memUsage is num ? memUsage.toInt() : (double.tryParse(memUsage.toString())?.toInt() ?? 0));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isOnline ? Colors.green : Colors.amber).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.laptop, color: isOnline ? Colors.green : Colors.amber, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device['name']?.toString() ?? 'My Laptop',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          device['os']?.toString() ?? (isOnline ? 'Online' : 'Offline'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.amber[600],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isOnline ? Colors.green : Colors.amber[600]!,
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'ONLINE' : 'OFFLINE (LAST KNOWN)',
                    style: TextStyle(
                      color: isOnline ? Colors.green[400] : Colors.amber[400],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 0.5),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('CPU', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('$cpuPct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _usageColor(cpuPct))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: cpuPct / 100,
                            backgroundColor: _usageColor(cpuPct).withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(_usageColor(cpuPct)),
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${cpu['cores'] ?? 0} Cores', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('RAM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('$memPct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _usageColor(memPct))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: memPct / 100,
                            backgroundColor: _usageColor(memPct).withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(_usageColor(memPct)),
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${mem['used'] ?? 0}/${mem['total'] ?? 0} GB', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        battery['isCharging'] == true ? Icons.battery_charging_full : Icons.battery_std,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        battery['hasBattery'] == true
                            ? '${battery['percent'] is num ? (battery['percent'] as num).toInt() : (double.tryParse(battery['percent']?.toString() ?? '')?.toInt() ?? 0)}%${battery['isCharging'] == true ? ' Charging' : ''}'
                            : 'Plugged In',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _quickActionButton(
                        Icons.lock_outline,
                        'Lock',
                        () => _sendQuickCommand('lock', 'Lock Laptop'),
                        cs,
                        isEnabled: isOnline,
                      ),
                      const SizedBox(width: 8),
                      _quickActionButton(
                        Icons.volume_mute,
                        'Mute',
                        () => _sendQuickCommand('volume_mute', 'Mute Laptop'),
                        cs,
                        isEnabled: isOnline,
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

  Widget _quickActionButton(IconData icon, String label, VoidCallback onPressed, ColorScheme cs, {bool isEnabled = true}) {
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: isEnabled ? null : cs.onSurface.withValues(alpha: 0.3)),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isEnabled ? null : cs.onSurface.withValues(alpha: 0.3),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          side: BorderSide(
            color: isEnabled ? cs.outline.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.1),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Color _usageColor(int percent) {
    if (percent < 50) return Colors.green;
    if (percent < 80) return Colors.orange;
    return Colors.red;
  }

  Widget _buildAiBanner(BuildContext context, ColorScheme cs) {
    final items = [
      (Icons.image_outlined, 'Generate\nImage', const Color(0xFF6C63FF),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageGenScreen()))),
      (Icons.search, 'Web\nSearch', const Color(0xFF2196F3),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebSearchScreen()))),
      (Icons.map_outlined, 'Maps &\nRoutes', const Color(0xFF4CAF50),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapsScreen()))),
      (Icons.camera_alt_outlined, 'Analyze\nPhoto', const Color(0xFF00BCD4),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageAnalysisScreen()))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Quick Actions',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: items.map((item) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: item.$1 == items.last.$1 ? 0 : 8),
                child: GestureDetector(
                  onTap: item.$4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: item.$3.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: item.$3.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(item.$1, color: item.$3, size: 22),
                        const SizedBox(height: 6),
                        Text(item.$2,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 10, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}