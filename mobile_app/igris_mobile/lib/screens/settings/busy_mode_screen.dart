import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:igris_mobile/services/notification_handler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BusyModeScreen extends StatefulWidget {
  const BusyModeScreen({super.key});

  @override
  State<BusyModeScreen> createState() => _BusyModeScreenState();
}

class _BusyModeScreenState extends State<BusyModeScreen> {
  final _dio = Dio();
  final _replyCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _busyModeEnabled = false;
  bool _rejectCalls = false;
  bool _notifyTelegram = true;
  String? _error;
  bool _hasChanges = false;

  // Initial values to compare
  bool _initBusy = false;
  bool _initReject = false;
  bool _initNotify = true;
  String _initReply = '';

  String get _settingsUrl =>
      '${ConfigurationService().backendUrl}/settings';

  Future<Options> _authOptions() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token') ?? '';
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _replyCtrl.addListener(_checkForChanges);
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    final changed = _busyModeEnabled != _initBusy ||
        _rejectCalls != _initReject ||
        _notifyTelegram != _initNotify ||
        _replyCtrl.text.trim() != _initReply.trim();
    
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _loadSettings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final opts = await _authOptions();
      final resp = await _dio.get(_settingsUrl, options: opts);
      final s = resp.data['settings'] as Map<String, dynamic>;
      setState(() {
        _initBusy = s['busyModeEnabled'] as bool? ?? false;
        _initReject = s['busyModeRejectCalls'] as bool? ?? false;
        _initNotify = s['busyModeNotifyTelegram'] as bool? ?? true;
        _initReply = s['busyModeAutoReply'] as String? ??
            "Sanjay is Busy";
        
        _busyModeEnabled = _initBusy;
        _rejectCalls = _initReject;
        _notifyTelegram = _initNotify;
        _replyCtrl.text = _initReply;
        
        _loading = false;
        _hasChanges = false;
      });

      // Save locally for background service
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(key: 'busy_mode_enabled', value: _initBusy.toString());
      await secureStorage.write(key: 'busy_mode_reply', value: _initReply);
      await secureStorage.write(key: 'busy_mode_reject_calls', value: _initReject.toString());

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('busy_mode_enabled', _initBusy);
        await prefs.setBool('busy_mode_reject_calls', _initReject);
      } catch (e) {
        debugPrint('Failed to sync busy_mode_enabled to SharedPreferences: $e');
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final opts = await _authOptions();
      await _dio.put(_settingsUrl,
          data: {
            'busyModeEnabled': _busyModeEnabled,
            'busyModeAutoReply': _replyCtrl.text.trim(),
            'busyModeRejectCalls': _rejectCalls,
            'busyModeNotifyTelegram': _notifyTelegram,
          },
          options: opts);
      
      // Update local storage for background service
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(key: 'busy_mode_enabled', value: _busyModeEnabled.toString());
      await secureStorage.write(key: 'busy_mode_reply', value: _replyCtrl.text.trim());
      await secureStorage.write(key: 'busy_mode_reject_calls', value: _rejectCalls.toString());

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('busy_mode_enabled', _busyModeEnabled);
        await prefs.setBool('busy_mode_reject_calls', _rejectCalls);
      } catch (e) {
        debugPrint('Failed to sync busy_mode_enabled to SharedPreferences: $e');
      }
      
      // Start/stop background service accordingly
      if (_busyModeEnabled) {
        await NotificationHandlerService().startService();
      } else {
        await NotificationHandlerService().stopService();
      }

      // Update initial values
      _initBusy = _busyModeEnabled;
      _initReject = _rejectCalls;
      _initNotify = _notifyTelegram;
      _initReply = _replyCtrl.text.trim();

      if (mounted) {
        setState(() {
          _saving = false;
          _hasChanges = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Monitor Mode settings saved ✅'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _quickToggle() async {
    try {
      final opts = await _authOptions();
      final resp = await _dio.post('$_settingsUrl/busy-mode/toggle', options: opts);
      final newState = resp.data['busyModeEnabled'] as bool;

      if (newState) {
        final granted = await NotificationHandlerService().requestPermissions();
        if (granted) {
          await NotificationHandlerService().startService();
        }
      } else {
        await NotificationHandlerService().stopService();
      }

      setState(() {
        _busyModeEnabled = newState;
        _initBusy = newState; // Sync initial state for quick toggle
        _checkForChanges();
      });
      
      // Update local storage for background service
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(key: 'busy_mode_enabled', value: newState.toString());

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('busy_mode_enabled', newState);
      } catch (e) {
        debugPrint('Failed to sync busy_mode_enabled to SharedPreferences: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Busy Mode'),
        actions: [
          if (!_loading && _error == null) ...[
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_hasChanges)
              TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: _loadSettings,
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Status Banner ──────────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _busyModeEnabled
                              ? [Colors.orange.shade700, Colors.red.shade600]
                              : [cs.primaryContainer, cs.secondaryContainer],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _busyModeEnabled
                                ? Icons.do_not_disturb_on
                                : Icons.check_circle,
                            size: 48,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _busyModeEnabled ? 'AI Assistant ON' : 'AI Assistant OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _busyModeEnabled
                                ? 'Calls are routed to AI assistant while in Silent Mode'
                                : 'AI Call Assistant is currently disabled',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _quickToggle,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.25),
                              foregroundColor: Colors.white,
                            ),
                            icon: Icon(_busyModeEnabled
                                ? Icons.toggle_off
                                : Icons.toggle_on),
                            label: Text(
                              _busyModeEnabled ? 'Turn OFF' : 'Turn ON',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Call Summaries Link ──────────────────────────────────────
                    if (_busyModeEnabled)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Call Summaries'),
                        subtitle: const Text('View summaries from your AI assistant'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pushNamed(context, '/busy-mode-summaries');
                        },
                      ),
                    const SizedBox(height: 24),

                    // ── Settings Card ──────────────────────────────────────
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Enable Monitor Mode'),
                            subtitle: const Text('Auto-reply when phone is in Silent Mode (no vibration)'),
                            secondary: const Icon(Icons.notifications_active),
                            value: _busyModeEnabled,
                            onChanged: (v) async {
                              if (v) {
                                final granted = await NotificationHandlerService().requestPermissions();
                                if (granted) {
                                  await NotificationHandlerService().startService();
                                } else {
                                  v = false;
                                }
                              } else {
                                await NotificationHandlerService().stopService();
                              }
                              setState(() {
                                _busyModeEnabled = v;
                                _checkForChanges();
                              });
                            },
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SwitchListTile(
                            title: const Text('Reject incoming calls'),
                            subtitle: const Text('Auto-decline calls when busy'),
                            secondary: const Icon(Icons.call_end),
                            value: _rejectCalls,
                            onChanged: (v) => setState(() {
                              _rejectCalls = v;
                              _checkForChanges();
                            }),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SwitchListTile(
                            title: const Text('Telegram alerts'),
                            subtitle: const Text('Notify you on Telegram when someone messages'),
                            secondary: const Icon(Icons.send),
                            value: _notifyTelegram,
                            onChanged: (v) => setState(() {
                              _notifyTelegram = v;
                              _checkForChanges();
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Auto Reply Card ────────────────────────────────────
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.reply, color: cs.primary),
                                const SizedBox(width: 8),
                                Text('Auto-Reply Message',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This message is sent to people who call or message you while phone is in Silent Mode.',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _replyCtrl,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: "Sanjay is Busy...",
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => _replyCtrl.clear(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Quick presets
                            Wrap(
                              spacing: 8,
                              children: [
                                _preset('Meeting'),
                                _preset('Driving'),
                                _preset('Sleeping'),
                                _preset('At class'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Save Button ────────────────────────────────────────
                    if (_hasChanges)
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: const Text('Save Settings'),
                      ),
                  ],
                ),
    );
  }

  Widget _preset(String text) => ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 12)),
        onPressed: () => setState(() {
          _replyCtrl.text = "Sanjay is Busy ($text)";
          _checkForChanges();
        }),
      );
}
