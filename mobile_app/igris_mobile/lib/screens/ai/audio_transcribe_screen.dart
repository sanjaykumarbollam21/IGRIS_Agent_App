import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:igris_mobile/services/ai_service.dart';

class AudioTranscribeScreen extends StatefulWidget {
  const AudioTranscribeScreen({super.key});

  @override
  State<AudioTranscribeScreen> createState() => _AudioTranscribeScreenState();
}

class _AudioTranscribeScreenState extends State<AudioTranscribeScreen> {
  final _ai = AiService();
  File? _audioFile;
  String _transcription = '';
  bool _loading = false;
  String? _error;
  String _language = 'auto';

  static const _languages = {
    'auto': 'Auto Detect',
    'en': 'English',
    'hi': 'Hindi',
    'ta': 'Tamil',
    'te': 'Telugu',
    'ml': 'Malayalam',
    'bn': 'Bengali',
    'mr': 'Marathi',
    'ar': 'Arabic',
    'zh': 'Chinese',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ja': 'Japanese',
    'ko': 'Korean',
  };

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _audioFile = File(result.files.first.path!);
      _transcription = '';
      _error = null;
    });
  }

  Future<void> _transcribe() async {
    if (_audioFile == null) return;
    setState(() { _loading = true; _transcription = ''; _error = null; });

    try {
      final bytes = await _audioFile!.readAsBytes();
      final ext = _audioFile!.path.split('.').last.toLowerCase();
      final mimeMap = {
        'm4a': 'audio/m4a', 'mp3': 'audio/mpeg', 'wav': 'audio/wav',
        'ogg': 'audio/ogg', 'flac': 'audio/flac', 'aac': 'audio/aac',
        'webm': 'audio/webm',
      };
      final mime = mimeMap[ext] ?? 'audio/m4a';
      final result = await _ai.transcribeAudio(bytes,
          mimeType: mime);
      setState(() => _transcription = result);
    } catch (e) {
      setState(() => _error = 'Transcription failed: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  String get _fileName => _audioFile?.path.split(Platform.pathSeparator).last ?? '';
  String get _fileSize {
    if (_audioFile == null) return '';
    final bytes = _audioFile!.lengthSync();
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcribe Audio'),
        actions: [
          if (_transcription.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.share(_transcription),
              tooltip: 'Share transcription',
            ),
        ],
      ),
      body: Column(
        children: [
          // File picker area
          GestureDetector(
            onTap: _pickAudio,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _audioFile != null
                      ? cs.primary
                      : cs.outline.withValues(alpha: 0.4),
                  width: _audioFile != null ? 2 : 1,
                  style: BorderStyle.solid,
                ),
              ),
              child: _audioFile == null
                  ? Column(
                      children: [
                        Icon(Icons.audio_file_outlined, size: 56,
                            color: cs.primary.withValues(alpha: 0.6)),
                        const SizedBox(height: 12),
                        Text('Tap to pick an audio file',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text('Supports: MP3, M4A, WAV, OGG, FLAC, AAC',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.audiotrack, color: cs.primary, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fileName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(_fileSize,
                                  style: TextStyle(
                                      fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _pickAudio,
                          child: const Text('Change'),
                        ),
                      ],
                    ),
            ),
          ),

          // Language + Transcribe button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: InputDecoration(
                      labelText: 'Language',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    items: _languages.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _language = v!),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: (_audioFile == null || _loading) ? null : _transcribe,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.graphic_eq),
                  label: Text(_loading ? 'Working...' : 'Transcribe'),
                ),
              ],
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),

          const SizedBox(height: 12),

          // Transcription result
          Expanded(
            child: _transcription.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.subtitles_outlined, size: 56,
                            color: cs.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('Transcription will appear here',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: cs.primary),
                            const SizedBox(height: 16),
                            const Text('Transcribing your audio...'),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _transcription,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
