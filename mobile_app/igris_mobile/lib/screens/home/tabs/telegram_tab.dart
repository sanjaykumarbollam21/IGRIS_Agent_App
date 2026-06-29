import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramTab extends ConsumerStatefulWidget {
  const TelegramTab({super.key});

  @override
  ConsumerState<TelegramTab> createState() => _TelegramTabState();
}

class _TelegramTabState extends ConsumerState<TelegramTab> {
  final _secureStorage = const FlutterSecureStorage();
  final _botUsernameController = TextEditingController();
  final _telegramIdController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  // Available bot commands
  final List<Map<String, String>> _commands = [
    {
      'command': '/start',
      'description': 'Start the bot and register your account'
    },
    {
      'command': '/help',
      'description': 'Show all available commands'
    },
    {
      'command': '/attendance',
      'description': 'Mark attendance for current session'
    },
    {
      'command': '/stats',
      'description': 'View your attendance statistics'
    },
    {
      'command': '/schedule',
      'description': 'View today\'s class schedule'
    },
    {
      'command': '/remind',
      'description': 'Set a reminder (e.g., /remind 30m Study math)'
    },
    {
      'command': '/ask',
      'description': 'Ask IGRIS AI anything'
    },
    {
      'command': '/status',
      'description': 'Check IGRIS system status'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _botUsernameController.dispose();
    _telegramIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _botUsernameController.text =
        await _secureStorage.read(key: 'telegram_bot_username') ??
            'igris_ai_bot';
    _telegramIdController.text =
        await _secureStorage.read(key: 'telegram_user_id') ?? '';
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    await _secureStorage.write(
        key: 'telegram_bot_username',
        value: _botUsernameController.text.trim());
    await _secureStorage.write(
        key: 'telegram_user_id',
        value: _telegramIdController.text.trim());
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Telegram settings saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openTelegram() async {
    final botUsername = _botUsernameController.text.trim();
    if (botUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a bot username first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final uri = Uri.parse('https://t.me/$botUsername');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Telegram. Is it installed?'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        _buildHeaderCard(),
        const SizedBox(height: 16),

        // Open in Telegram button
        ElevatedButton.icon(
          onPressed: _openTelegram,
          icon: const Icon(Icons.telegram),
          label: const Text('Open in Telegram'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0088CC),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Bot Settings
        _buildSettingsSection(),
        const SizedBox(height: 24),

        // Available Commands
        Text('Bot Commands',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ..._commands.map((cmd) => _buildCommandItem(cmd)),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF0088CC).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.telegram,
                  size: 40, color: Color(0xFF0088CC)),
            ),
            const SizedBox(height: 16),
            Text('IGRIS Telegram Bot',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Control IGRIS directly from Telegram. Mark attendance, ask questions, set reminders, and more.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bot Settings',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _botUsernameController,
              decoration: InputDecoration(
                labelText: 'Bot Username',
                hintText: 'igris_ai_bot',
                prefixIcon: const Icon(Icons.smart_toy_outlined),
                prefixText: '@',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telegramIdController,
              decoration: InputDecoration(
                labelText: 'Your Telegram ID',
                hintText: 'Enter your numeric Telegram ID',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandItem(Map<String, String> cmd) {
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
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0088CC).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.code, color: Color(0xFF0088CC), size: 20),
        ),
        title: Text(
          cmd['command']!,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(cmd['description']!),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cmd['command']!));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied ${cmd['command']}'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }
}
