// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:igris_mobile/widgets/common/setting_tile.dart';
import 'package:igris_mobile/providers/theme_provider.dart';
import 'package:igris_mobile/providers/auth_provider.dart';
import 'package:igris_mobile/screens/auth/login_screen.dart';
import 'package:igris_mobile/screens/settings/profile_screen.dart';
import 'package:igris_mobile/screens/settings/api_keys_screen.dart';
import 'package:igris_mobile/screens/settings/credentials_screen.dart';
import 'package:igris_mobile/screens/settings/status_screen.dart';
import 'package:igris_mobile/screens/settings/voice_settings_screen.dart';
import 'package:igris_mobile/screens/settings/busy_mode_screen.dart';
import 'package:igris_mobile/screens/settings/wake_word_settings_screen.dart';
import 'package:igris_mobile/screens/tools/gmail_screen.dart';
import 'package:igris_mobile/screens/tools/calendar_screen.dart';
import 'package:igris_mobile/screens/tools/conversation_history_screen.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authStateProviderNotifier.notifier).logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _showServerSettingsDialog() {
    final config = ConfigurationService();
    final urlController = TextEditingController(text: config.backendUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configure the backend API URL for IGRIS.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '• Emulator: http://10.0.2.2:8080/api\n• Physical Phone: http://<your-pc-ip>:8080/api',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'Backend URL',
                hintText: 'http://ip-address:8080/api',
                prefixIcon: const Icon(Icons.dns_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              config.resetBackendUrl();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL reset to default')),
              );
            },
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                config.setBackendUrl(newUrl);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Server URL updated: $newUrl')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showThemePicker() {
    final current = ref.read(themeModeProvider);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Theme'),
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('Light'),
            value: ThemeMode.light,
            groupValue: current,
            onChanged: (v) { ref.read(themeModeProvider.notifier).state = v!; Navigator.pop(ctx); },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dark'),
            value: ThemeMode.dark,
            groupValue: current,
            onChanged: (v) { ref.read(themeModeProvider.notifier).state = v!; Navigator.pop(ctx); },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('System'),
            value: ThemeMode.system,
            groupValue: current,
            onChanged: (v) { ref.read(themeModeProvider.notifier).state = v!; Navigator.pop(ctx); },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final themeLabel = switch (themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),

        // ── System ──
        SettingTile(
          title: 'System Status',
          leadingIcon: Icons.monitor_heart_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const StatusScreen()),
        ),
        SettingTile(
          title: 'Server Settings',
          leadingIcon: Icons.dns_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: _showServerSettingsDialog,
        ),
        const Divider(height: 1),

        // ── Account ──
        SettingTile(
          title: 'Profile',
          leadingIcon: Icons.account_circle_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const ProfileScreen()),
        ),
        SettingTile(
          title: 'Credentials',
          leadingIcon: Icons.vpn_key_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const CredentialsScreen()),
        ),
        SettingTile(
          title: 'API Keys',
          leadingIcon: Icons.key_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const ApiKeysScreen()),
        ),
        const Divider(height: 1),

        // ── Voice ──
        SettingTile(
          title: 'Voice Agent',
          leadingIcon: Icons.record_voice_over_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const VoiceSettingsScreen()),
        ),
        const Divider(height: 1),

        // ── Wake Word ──
        SettingTile(
          title: 'Wake Word — "Hey IGRIS"',
          leadingIcon: Icons.mic_none_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const WakeWordSettingsScreen()),
        ),
        const Divider(height: 1),

        // ── Busy Mode ──
        SettingTile(
          title: 'Busy Mode',
          leadingIcon: Icons.do_not_disturb_on_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const BusyModeScreen()),
        ),
        const Divider(height: 1),

        // ── Connected Services ──
        SettingTile(
          title: 'Gmail',
          leadingIcon: Icons.mail_outline,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const GmailScreen()),
        ),
        SettingTile(
          title: 'Calendar',
          leadingIcon: Icons.calendar_month_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const CalendarScreen()),
        ),
        SettingTile(
          title: 'Chat History',
          leadingIcon: Icons.history,
          trailingIcon: Icons.chevron_right,
          onTap: () => _navigate(const ConversationHistoryScreen()),
        ),
        const Divider(height: 1),

        // ── Appearance ──
        SettingTile(
          title: 'Theme Mode',
          leadingIcon: Icons.brightness_6_outlined,
          trailingValue: themeLabel,
          onTap: _showThemePicker,
        ),
        const Divider(height: 1),

        // ── About ──
        SettingTile(
          title: 'About IGRIS',
          leadingIcon: Icons.info_outlined,
          trailingIcon: Icons.chevron_right,
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: 'IGRIS',
              applicationVersion: '4.0.0',
              applicationLegalese: '\u00a9 2026 IGRIS Project',
              children: [
                const SizedBox(height: 16),
                const Text(
                    'Intelligent General-purpose Robotic Intelligence System'),
              ],
            );
          },
        ),
        const Divider(height: 1),

        // ── Logout ──
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ElevatedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Version 4.0.0',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ),
      ],
    );
  }
}