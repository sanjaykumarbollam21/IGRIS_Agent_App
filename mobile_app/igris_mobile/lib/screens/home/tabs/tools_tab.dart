import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:igris_mobile/screens/tools/device_control_screen.dart';
import 'package:igris_mobile/screens/tools/automations_screen.dart';
import 'package:igris_mobile/screens/tools/calendar_screen.dart';
import 'package:igris_mobile/screens/tools/maps_screen.dart';
import 'package:igris_mobile/screens/tools/gmail_screen.dart';
import 'package:igris_mobile/screens/tools/conversation_history_screen.dart';
import 'package:igris_mobile/screens/tools/task_manager_screen.dart';
import 'package:igris_mobile/screens/settings/busy_mode_screen.dart';

class ToolsTab extends ConsumerWidget {
  const ToolsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── Communication ──────────────────────────────────────────────
        _section(context, 'Communication', Icons.chat, cs.primary, [
          _tile(context,
            icon: Icons.message,
            title: 'Send Message',
            subtitle: 'Send SMS or WhatsApp',
            onTap: () => launchUrl(Uri(scheme: 'sms', path: '')),
          ),
          _tile(context,
            icon: Icons.phone,
            title: 'Make Call',
            subtitle: 'Open phone dialer',
            onTap: () => launchUrl(Uri(scheme: 'tel', path: '')),
          ),
          _tile(context,
            icon: Icons.mail_outline,
            title: 'Gmail',
            subtitle: 'Read inbox & send emails',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GmailScreen())),
          ),
          _tile(context,
            icon: Icons.history,
            title: 'Chat History',
            subtitle: 'View IGRIS conversation logs',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ConversationHistoryScreen())),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Productivity ──
        _section(context, 'Productivity', Icons.event_note, cs.secondary, [
          _tile(context,
            icon: Icons.task_alt,
            title: 'Task Manager',
            subtitle: 'To-dos, priorities & reminders',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TaskManagerScreen())),
          ),
          _tile(context,
            icon: Icons.calendar_month,
            title: 'Calendar',
            subtitle: 'View schedule & create events',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CalendarScreen())),
          ),
          _tile(context,
            icon: Icons.map,
            title: 'Maps & Navigation',
            subtitle: 'Directions and nearby places',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MapsScreen())),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Device Control ─────────────────────────────────────────────
        _section(context, 'Device Control', Icons.devices, cs.secondary, [
          _tile(context,
            icon: Icons.laptop,
            title: 'Connected Devices',
            subtitle: 'Control your laptop remotely',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DeviceControlScreen())),
          ),
          _tile(context,
            icon: Icons.apps,
            title: 'Open App',
            subtitle: 'Launch any installed app',
            onTap: () => _showAppLauncher(context),
          ),
          _tile(context,
            icon: Icons.web,
            title: 'Web Search',
            subtitle: 'Search the internet via IGRIS AI',
            onTap: () => _showSearchDialog(context),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Automation & Busy Mode ─────────────────────────────────────
        _section(context, 'Automation & Busy Mode', Icons.auto_awesome,
            cs.tertiary, [
          _tile(context,
            icon: Icons.settings_suggest,
            title: 'Automations',
            subtitle: 'Time-based & event-triggered tasks',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AutomationsScreen())),
          ),
          _tile(context,
            icon: Icons.do_not_disturb_on,
            title: 'Busy Mode',
            subtitle: 'Auto-reply while you\'re unavailable',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BusyModeScreen())),
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Builders ─────────────────────────────────────────────────────────────

  Widget _section(BuildContext context, String title, IconData icon,
      Color color, List<Widget> children) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 10),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      dense: true,
      onTap: onTap,
    );
  }

  // ── App Launcher ──────────────────────────────────────────────────────────
  void _showAppLauncher(BuildContext context) {
    final apps = {
      'YouTube': 'https://youtube.com',
      'WhatsApp': 'https://wa.me',
      'Instagram': 'https://instagram.com',
      'Telegram': 'https://t.me',
      'Twitter/X': 'https://twitter.com',
      'Spotify': 'https://open.spotify.com',
      'Gmail': 'mailto:',
      'Maps': 'https://maps.google.com',
      'Chrome': 'https://google.com',
    };
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Open App'),
        children: apps.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(ctx);
                    launchUrl(Uri.parse(e.value),
                        mode: LaunchMode.externalApplication);
                  },
                  child: Text(e.key),
                ))
            .toList(),
      ),
    );
  }

  // ── Web Search ────────────────────────────────────────────────────────────
  void _showSearchDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Web Search'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'Search query',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
          onSubmitted: (_) {
            Navigator.pop(ctx);
            final q = ctrl.text.trim();
            if (q.isNotEmpty) {
              launchUrl(
                  Uri.parse('https://google.com/search?q=${Uri.encodeComponent(q)}'),
                  mode: LaunchMode.externalApplication);
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final q = ctrl.text.trim();
              if (q.isNotEmpty) {
                launchUrl(
                    Uri.parse('https://google.com/search?q=${Uri.encodeComponent(q)}'),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}