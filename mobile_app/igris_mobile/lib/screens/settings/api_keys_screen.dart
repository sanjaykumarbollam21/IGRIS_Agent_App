import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:igris_mobile/services/voice_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  final _secureStorage = const FlutterSecureStorage();

  // Controllers
  final _serverUrlCtrl   = TextEditingController();
  final _geminiCtrl      = TextEditingController();
  final _murfCtrl        = TextEditingController();
  final _hfCtrl          = TextEditingController();
  final _openAiCtrl      = TextEditingController();
  final _stabilityCtrl   = TextEditingController();

  // Visibility toggles
  bool _showGemini    = false;
  bool _showMurf      = false;
  bool _showHf        = false;
  bool _showOpenAi    = false;
  bool _showStability = false;

  bool _isLoading  = true;
  bool _isSaving   = false;
  bool _hasChanges = false;

  // Snapshots for change detection
  String _snapServer = '', _snapGemini = '', _snapMurf = '',
         _snapHf = '', _snapOpenAi = '', _snapStability = '';

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_serverUrlCtrl, _geminiCtrl, _murfCtrl, _hfCtrl, _openAiCtrl, _stabilityCtrl]) {
      c.addListener(_check);
    }
  }

  @override
  void dispose() {
    for (final c in [_serverUrlCtrl, _geminiCtrl, _murfCtrl, _hfCtrl, _openAiCtrl, _stabilityCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    final changed =
        _serverUrlCtrl.text.trim()  != _snapServer   ||
        _geminiCtrl.text.trim()     != _snapGemini    ||
        _murfCtrl.text.trim()       != _snapMurf      ||
        _hfCtrl.text.trim()         != _snapHf        ||
        _openAiCtrl.text.trim()     != _snapOpenAi    ||
        _stabilityCtrl.text.trim()  != _snapStability;
    if (changed != _hasChanges) setState(() => _hasChanges = changed);
  }

  Future<void> _load() async {
    _snapServer    = ConfigurationService().backendUrl;
    _snapGemini    = await _secureStorage.read(key: 'gemini_api_key')    ?? '';
    _snapMurf      = await _secureStorage.read(key: 'murf_api_key')      ?? '';
    _snapHf        = await _secureStorage.read(key: 'hf_api_token')      ?? '';
    _snapOpenAi    = await _secureStorage.read(key: 'openai_api_key')    ?? '';
    _snapStability = await _secureStorage.read(key: 'stability_api_key') ?? '';

    _serverUrlCtrl.text  = _snapServer;
    _geminiCtrl.text     = _snapGemini;
    _murfCtrl.text       = _snapMurf;
    _hfCtrl.text         = _snapHf;
    _openAiCtrl.text     = _snapOpenAi;
    _stabilityCtrl.text  = _snapStability;

    setState(() { _isLoading = false; _hasChanges = false; });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final url = _serverUrlCtrl.text.trim();
    if (url.isNotEmpty) await ConfigurationService().setBackendUrl(url);

    await _secureStorage.write(key: 'gemini_api_key',    value: _geminiCtrl.text.trim());
    await _secureStorage.write(key: 'murf_api_key',      value: _murfCtrl.text.trim());
    await _secureStorage.write(key: 'hf_api_token',      value: _hfCtrl.text.trim());
    await _secureStorage.write(key: 'openai_api_key',    value: _openAiCtrl.text.trim());
    await _secureStorage.write(key: 'stability_api_key', value: _stabilityCtrl.text.trim());

    await VoiceService().reloadSettings();

    _snapServer    = url;
    _snapGemini    = _geminiCtrl.text.trim();
    _snapMurf      = _murfCtrl.text.trim();
    _snapHf        = _hfCtrl.text.trim();
    _snapOpenAi    = _openAiCtrl.text.trim();
    _snapStability = _stabilityCtrl.text.trim();

    setState(() { _isSaving = false; _hasChanges = false; });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys & Server'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_hasChanges)
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Security notice
                  _notice(context),
                  const SizedBox(height: 24),

                  // Image generation priority info
                  _imageGenInfo(context),
                  const SizedBox(height: 28),

                  // ── Server ───────────────────────────────────────────────
                  _sectionTitle('Backend Server'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _serverUrlCtrl,
                    label: 'Server URL',
                    hint: 'https://api.your-host.com/api',
                    icon: Icons.dns_outlined,
                    obscure: false,
                    showToggle: false,
                    onToggle: () {},
                  ),
                  const SizedBox(height: 28),

                  // ── AI Chat ──────────────────────────────────────────────
                  _sectionTitle('AI Chat — Google Gemini (optional)'),
                  _hint('Free at aistudio.google.com — enables direct Gemini chat'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _geminiCtrl,
                    label: 'Gemini API Key',
                    hint: 'AIza...',
                    icon: Icons.auto_awesome,
                    obscure: !_showGemini,
                    showToggle: true,
                    onToggle: () => setState(() => _showGemini = !_showGemini),
                    linkText: 'Get free key',
                    linkUrl: 'https://aistudio.google.com/apikey',
                  ),
                  const SizedBox(height: 28),

                  // ── Image Generation ─────────────────────────────────────
                  _sectionTitle('Image Generation (priority order)'),
                  const SizedBox(height: 4),

                  // 1. HuggingFace
                  _subTitle('1 · Hugging Face Token (Free — FLUX.1-schnell)'),
                  _hint('Best quality. Free account at huggingface.co → Settings → Access Tokens'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _hfCtrl,
                    label: 'HuggingFace Token',
                    hint: 'hf_...',
                    icon: Icons.hub_outlined,
                    obscure: !_showHf,
                    showToggle: true,
                    onToggle: () => setState(() => _showHf = !_showHf),
                    linkText: 'Get free token',
                    linkUrl: 'https://huggingface.co/settings/tokens',
                  ),
                  const SizedBox(height: 20),

                  // 2. OpenAI
                  _subTitle('2 · OpenAI API Key (Paid — DALL-E 3)'),
                  _hint('Highest quality. Requires OpenAI account with billing.'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _openAiCtrl,
                    label: 'OpenAI API Key',
                    hint: 'sk-...',
                    icon: Icons.bolt_outlined,
                    obscure: !_showOpenAi,
                    showToggle: true,
                    onToggle: () => setState(() => _showOpenAi = !_showOpenAi),
                    linkText: 'platform.openai.com',
                    linkUrl: 'https://platform.openai.com/api-keys',
                  ),
                  const SizedBox(height: 20),

                  // 3. Stability AI
                  _subTitle('3 · Stability AI Key (Paid — SDXL 1.0)'),
                  _hint('Requires Stability AI account.'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _stabilityCtrl,
                    label: 'Stability AI Key',
                    hint: 'sk-...',
                    icon: Icons.image_outlined,
                    obscure: !_showStability,
                    showToggle: true,
                    onToggle: () => setState(() => _showStability = !_showStability),
                    linkText: 'platform.stability.ai',
                    linkUrl: 'https://platform.stability.ai/account/keys',
                  ),
                  const SizedBox(height: 8),
                  _hint('5 · No key → Pollinations / Stable Horde (free, auto-fallback)'),
                  const SizedBox(height: 28),

                  // ── TTS ──────────────────────────────────────────────────
                  _sectionTitle('Voice — Murf AI (optional)'),
                  _hint('Premium TTS voices. Free trial at murf.ai'),
                  const SizedBox(height: 8),
                  _field(
                    controller: _murfCtrl,
                    label: 'Murf API Key',
                    hint: 'murf_...',
                    icon: Icons.record_voice_over_outlined,
                    obscure: !_showMurf,
                    showToggle: true,
                    onToggle: () => setState(() => _showMurf = !_showMurf),
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  if (_hasChanges)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Copy auth token
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final token = await _secureStorage.read(key: 'auth_token');
                        if (token == null) return;
                        await Clipboard.setData(ClipboardData(text: token));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Auth token copied'), behavior: SnackBarBehavior.floating),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy Auth Token (for Desktop Agent)'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _notice(BuildContext ctx) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      Icon(Icons.lock_outline, color: Theme.of(ctx).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(
        'All keys are encrypted on-device. They are never sent to IGRIS servers.',
        style: Theme.of(ctx).textTheme.bodySmall,
      )),
    ]),
  );

  Widget _imageGenInfo(BuildContext ctx) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.purple.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.image_search, color: Colors.purple, size: 18),
        const SizedBox(width: 8),
        Text('Image Generation Priority', style: Theme.of(ctx).textTheme.labelLarge?.copyWith(color: Colors.purple)),
      ]),
      const SizedBox(height: 8),
      const Text('1 · Gemini Key → Imagen 3 (high quality, using your key)\n'
                 '2 · HuggingFace Token → FLUX.1-schnell (free, best quality)\n'
                 '3 · OpenAI Key → DALL-E 3 (premium)\n'
                 '4 · Stability AI Key → SDXL 1.0 (premium)\n'
                 '5 · No key → Pollinations / Stable Horde (free, auto-fallback)',
        style: TextStyle(fontSize: 12, height: 1.7)),
    ]),
  );

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
  Widget _subTitle(String t)     => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500));
  Widget _hint(String t)         => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(t, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool obscure,
    required bool showToggle,
    required VoidCallback onToggle,
    String? linkText,
    String? linkUrl,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: showToggle
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: onToggle,
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    if (linkText != null && linkUrl != null)
      TextButton.icon(
        onPressed: () => _openUrl(linkUrl),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(Icons.open_in_new, size: 14),
        label: Text(linkText, style: const TextStyle(fontSize: 12)),
      ),
  ]);
}
