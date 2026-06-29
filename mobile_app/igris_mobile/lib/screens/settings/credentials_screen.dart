import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final _secureStorage = const FlutterSecureStorage();

  // Telegram
  final _telegramBotToken = TextEditingController();
  final _telegramChatId = TextEditingController();
  bool _obscureTelegram = true;

  bool _isLoading = true;
  bool _hasChanges = false;

  String _initToken = '';
  String _initChatId = '';

  @override
  void initState() {
    super.initState();
    _load();
    _telegramBotToken.addListener(_checkChanges);
    _telegramChatId.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _telegramBotToken.dispose();
    _telegramChatId.dispose();
    super.dispose();
  }

  void _checkChanges() {
    final changed = _telegramBotToken.text.trim() != _initToken ||
        _telegramChatId.text.trim() != _initChatId;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _load() async {
    _initToken = await _secureStorage.read(key: 'telegram_bot_token') ?? '';
    _initChatId = await _secureStorage.read(key: 'telegram_chat_id') ?? '';
    
    _telegramBotToken.text = _initToken;
    _telegramChatId.text = _initChatId;
    
    setState(() {
      _isLoading = false;
      _hasChanges = false;
    });
  }

  Future<void> _save() async {
    await _secureStorage.write(
        key: 'telegram_bot_token', value: _telegramBotToken.text.trim());
    await _secureStorage.write(
        key: 'telegram_chat_id', value: _telegramChatId.text.trim());

    _initToken = _telegramBotToken.text.trim();
    _initChatId = _telegramChatId.text.trim();

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All credentials saved securely'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credentials'),
        actions: [
          if (_hasChanges)
            TextButton(onPressed: _save, child: const Text('Save All')),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Security notice
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All credentials are encrypted and stored locally on your device.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Telegram ──
                  _buildSectionHeader('Telegram Bot', Icons.telegram),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _telegramBotToken,
                    obscureText: _obscureTelegram,
                    decoration: _inputDecor(
                      'Bot Token',
                      'Enter your Telegram bot token',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureTelegram
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscureTelegram = !_obscureTelegram),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _telegramChatId,
                    decoration: _inputDecor(
                      'Chat ID',
                      'Your Telegram numeric chat ID',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  InputDecoration _inputDecor(String label, String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
