import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  static const _channel = MethodChannel('com.igris.intents');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _item(context, Icons.message, 'Messages',
                const Color(0xFF4CAF50), _openSms),
            _item(context, Icons.camera_alt, 'Camera',
                const Color(0xFF7B61FF), _openCamera),
            _item(context, Icons.access_time, 'Clock',
                const Color(0xFFFF9800), _openClock),
            _item(context, Icons.web, 'Browser',
                const Color(0xFF2196F3), _openBrowser),
            _item(context, Icons.telegram, 'Telegram',
                const Color(0xFF29B6F6), _openTelegram),
            _item(context, Icons.apps, 'Apps',
                Theme.of(context).colorScheme.tertiary, _openApps),
          ],
        ),
      ],
    );
  }

  Future<void> _openSms(BuildContext context) async {
    try { await launchUrl(Uri(scheme: 'sms', path: '')); } catch (_) {}
  }

  Future<void> _openCamera(BuildContext context) async {
    try {
      await _channel.invokeMethod('openCamera');
    } catch (_) {
      try { await _channel.invokeMethod('launchApp', {'package': 'com.android.camera'}); } catch (_) {}
    }
  }

  Future<void> _openClock(BuildContext context) async {
    try {
      await _channel.invokeMethod('openClock');
    } catch (_) {
      try { await _channel.invokeMethod('launchApp', {'package': 'com.google.android.deskclock'}); } catch (_) {}
    }
  }

  Future<void> _openApps(BuildContext context) async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {
      try { await launchUrl(Uri.parse('app-settings:'), mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

  Future<void> _openBrowser(BuildContext context) async {
    try {
      await launchUrl(Uri.parse('https://www.google.com'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openTelegram(BuildContext context) async {
    try {
      await launchUrl(Uri.parse('https://t.me'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _item(BuildContext context, IconData icon, String label,
      Color color, Future<void> Function(BuildContext) onTap) {
    return GestureDetector(
      onTap: () => onTap(context),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 6),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500, fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}