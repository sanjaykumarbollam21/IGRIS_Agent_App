// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:igris_mobile/services/wake_word_service.dart' show WakeWordService;

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final _secureStorage = const FlutterSecureStorage();
  final _tts = FlutterTts();
  double _speed = 0.45;
  double _pitch = 1.0;
  String _selectedVoice = '';
  // ignore: prefer_final_fields, unused_field
  String _selectedLocale = 'en-US';
  final List<Map<String, String>> _maleVoices = [];
  final List<Map<String, String>> _femaleVoices = [];
  final List<Map<String, String>> _otherVoices = [];
  bool _isLoading = true;
  bool _isTesting = false;
  bool _wakeWordEnabled = false;
  final _wakeWordSvc = WakeWordService();
  bool _hasChanges = false;

  // Initial values
  double _initSpeed = 0.45;
  double _initPitch = 1.0;
  String _initVoice = '';
  bool _initWake = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _checkChanges() {
    final changed = (_speed - _initSpeed).abs() > 0.01 ||
        (_pitch - _initPitch).abs() > 0.01 ||
        _selectedVoice != _initVoice ||
        _wakeWordEnabled != _initWake;
    
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _load() async {
    _initSpeed = double.tryParse(
            await _secureStorage.read(key: 'voice_speed') ?? '0.45') ?? 0.45;
    _initPitch = double.tryParse(
            await _secureStorage.read(key: 'voice_pitch') ?? '1.0') ?? 1.0;
    _initVoice = await _secureStorage.read(key: 'voice_name') ?? '';
    _selectedLocale = await _secureStorage.read(key: 'voice_locale') ?? 'en-US';
    _initWake = await _wakeWordSvc.isEnabled();

    _speed = _initSpeed;
    _pitch = _initPitch;
    _selectedVoice = _initVoice;
    _wakeWordEnabled = _initWake;

    await _tts.setLanguage('en-US');

    try {
      final rawVoices = await _tts.getVoices;
      if (rawVoices != null) {
        final enVoices = (rawVoices as List)
            .where((v) => v['locale']?.toString().startsWith('en') == true)
            .map<Map<String, String>>((v) => {
                  'name': v['name']?.toString() ?? '',
                  'locale': v['locale']?.toString() ?? '',
                })
            .toList();

        // Categorize by name heuristics
        for (final v in enVoices) {
          final name = v['name']!.toLowerCase();
          if (_isMaleVoice(name)) {
            _maleVoices.add(v);
          } else if (_isFemaleVoice(name)) {
            _femaleVoices.add(v);
          } else {
            _otherVoices.add(v);
          }
        }
      }
    } catch (_) {}

    setState(() {
      _isLoading = false;
      _hasChanges = false;
    });
  }

  bool _isMaleVoice(String name) {
    const maleIndicators = [
      'male', 'james', 'john', 'david', 'michael', 'robert', 'william',
      'daniel', 'mark', 'steve', 'tom', 'george', 'peter', 'henry',
      'charlie', 'oliver', 'benjamin', 'narration', 'hmm',
    ];
    return maleIndicators.any((m) => name.contains(m));
  }

  bool _isFemaleVoice(String name) {
    const femaleIndicators = [
      'female', 'samantha', 'victoria', 'karen', 'susan', 'emma', 'sarah',
      'elizabeth', 'jessica', 'jennifer', 'amanda', 'ashley', 'lisa',
      'maria', 'nicole', 'sophia', 'olivia', 'ava', 'mia', 'zoe',
    ];
    return femaleIndicators.any((f) => name.contains(f));
  }

  Future<void> _save() async {
    await _secureStorage.write(key: 'voice_speed', value: _speed.toString());
    await _secureStorage.write(key: 'voice_pitch', value: _pitch.toString());
    await _secureStorage.write(key: 'voice_name', value: _selectedVoice);
    await _secureStorage.write(key: 'voice_locale', value: _selectedLocale);
    
    await _wakeWordSvc.setEnabled(_wakeWordEnabled);

    // Apply settings
    await _tts.setSpeechRate(_speed);
    await _tts.setPitch(_pitch);
    await _tts.setVoice({'name': _selectedVoice, 'locale': _selectedLocale});

    _initSpeed = _speed;
    _initPitch = _pitch;
    _initVoice = _selectedVoice;
    _initWake = _wakeWordEnabled;

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice settings saved'),
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _testVoice(String voiceName, String locale) async {
    setState(() => _isTesting = true);
    await _tts.setSpeechRate(_speed);
    await _tts.setPitch(_pitch);
    await _tts.setVoice({'name': voiceName, 'locale': locale});
    await _tts.speak('Hello Sir. I am IGRIS, your personal AI assistant. How may I help you today?');
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _isTesting = false);
  }

  void _selectVoice(String name, String locale) {
    setState(() {
      _selectedVoice = name;
      _selectedLocale = locale;
      _checkChanges();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Agent'),
        actions: [
          if (_hasChanges)
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [

                _buildSlider('Speech Speed', _speed, 0.1, 1.0,
                    (v) => setState(() {
                      _speed = v;
                      _checkChanges();
                    }),
                    '${(_speed * 100).toInt()}%'),
                const SizedBox(height: 20),
                _buildSlider('Voice Pitch', _pitch, 0.5, 2.0,
                    (v) => setState(() {
                      _pitch = v;
                      _checkChanges();
                    }),
                    _pitch.toStringAsFixed(1)),
                const SizedBox(height: 24),

                // Male voices
                if (_maleVoices.isNotEmpty) ...[
                  _sectionHeader('Male Voices', Icons.male, Colors.blue),
                  const SizedBox(height: 8),
                  ..._maleVoices.take(10).map((v) => _voiceTile(v)),
                  const SizedBox(height: 20),
                ],

                // Female voices
                if (_femaleVoices.isNotEmpty) ...[
                  _sectionHeader('Female Voices', Icons.female, Colors.pink),
                  const SizedBox(height: 8),
                  ..._femaleVoices.take(10).map((v) => _voiceTile(v)),
                  const SizedBox(height: 20),
                ],

                // Other voices
                if (_otherVoices.isNotEmpty) ...[
                  _sectionHeader('Other Voices', Icons.record_voice_over, Colors.grey),
                  const SizedBox(height: 8),
                  ..._otherVoices.take(15).map((v) => _voiceTile(v)),
                ],

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _voiceTile(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    final isSelected = _selectedVoice == name;

    // Extract readable name
    final displayName = name
        .replaceAll('en-us-x-', '')
        .replaceAll('en-gb-x-', '')
        .replaceAll('en-au-x-', '')
        .replaceAll('-local', '')
        .replaceAll('-network', ' (HD)')
        .replaceAll('#', ' ')
        .trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
            : null,
      ),
      child: ListTile(
        leading: Radio<String>(
          value: name,
          groupValue: _selectedVoice,
          onChanged: (_) => _selectVoice(name, locale),
        ),
        title: Text(displayName.isNotEmpty ? displayName : name,
            style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(locale, style: const TextStyle(fontSize: 11)),
        trailing: IconButton(
          onPressed: _isTesting ? null : () => _testVoice(name, locale),
          icon: Icon(Icons.play_circle_outline,
              color: Theme.of(context).colorScheme.primary),
          tooltip: 'Test this voice',
        ),
        dense: true,
        onTap: () => _selectVoice(name, locale),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String display) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            Text(display,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(value: value, min: min, max: max, divisions: 20,
            onChanged: onChanged),
      ],
    );
  }
}

