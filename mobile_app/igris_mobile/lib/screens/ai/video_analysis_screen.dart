import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class VideoAnalysisScreen extends ConsumerStatefulWidget {
  const VideoAnalysisScreen({super.key});

  @override
  ConsumerState<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends ConsumerState<VideoAnalysisScreen> {
  final _storage = const FlutterSecureStorage();
  final _urlCtrl = TextEditingController();

  File? _videoFile;
  String _result = '';
  bool _loading = false;
  String? _error;
  String _task = 'summarize';
  bool _useUrl = false;

  static const _tasks = {
    'summarize': ('Summarize', Icons.summarize_outlined),
    'extract_highlights': ('Key Moments', Icons.star_outline),
    'transcribe': ('Transcribe', Icons.subtitles_outlined),
    'describe': ('Describe', Icons.description_outlined),
  };

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _videoFile = File(result.files.first.path!);
      _result = '';
      _error = null;
    });
  }

  Future<void> _analyze() async {
    final usingUrl = _useUrl;
    final url = _urlCtrl.text.trim();
    if (usingUrl && url.isEmpty) return;
    if (!usingUrl && _videoFile == null) return;

    setState(() { _loading = true; _result = ''; _error = null; });

    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        setState(() => _error = 'Not authenticated.');
        return;
      }

      Map<String, dynamic> body;
      if (usingUrl) {
        body = { 'videoUrl': url, 'task': _task };
      } else {
        final bytes = await _videoFile!.readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = _videoFile!.path.split('.').last.toLowerCase();
        final mimeMap = {
          'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/avi',
          'mkv': 'video/x-matroska', 'webm': 'video/webm',
        };
        body = {
          'videoData': b64,
          'mimeType': mimeMap[ext] ?? 'video/mp4',
          'task': _task,
        };
      }

      final resp = await http.post(
        Uri.parse('$baseUrl/api/ai/analyze-video'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(minutes: 3));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _result = data['analysis'] ?? 'No result returned.');
      } else {
        setState(() => _error = 'Server error ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Analysis failed: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyze Video'),
        actions: [
          if (_result.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.share(_result),
            ),
        ],
      ),
      body: Column(
        children: [
          // Source toggle
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Upload File'), icon: Icon(Icons.upload_file)),
                ButtonSegment(value: true, label: Text('Video URL'), icon: Icon(Icons.link)),
              ],
              selected: {_useUrl},
              onSelectionChanged: (s) => setState(() { _useUrl = s.first; _result = ''; }),
            ),
          ),

          // File picker or URL input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _useUrl
                ? TextField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=...',
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                : GestureDetector(
                    onTap: _pickVideo,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _videoFile != null ? cs.primary : cs.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: _videoFile == null
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.video_file_outlined, color: cs.primary),
                                const SizedBox(width: 10),
                                const Text('Pick a video file (MP4, MOV, AVI...)'),
                              ],
                            )
                          : Row(
                              children: [
                                Icon(Icons.video_file, color: cs.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _videoFile!.path.split(Platform.pathSeparator).last,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TextButton(onPressed: _pickVideo, child: const Text('Change')),
                              ],
                            ),
                    ),
                  ),
          ),

          // Task chips
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _tasks.entries.map((e) {
                final selected = _task == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(e.value.$2, size: 16),
                    label: Text(e.value.$1),
                    selected: selected,
                    onSelected: (_) => setState(() => _task = e.key),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Analyze button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _loading ? null : _analyze,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_circle_outline),
              label: Text(_loading ? 'Analyzing...' : 'Analyze with Gemini'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),

          // Result
          Expanded(
            child: _result.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_library_outlined, size: 56,
                            color: cs.onSurface.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('Analysis result will appear here',
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
                            const Text('Analyzing video with Gemini...'),
                            const SizedBox(height: 6),
                            Text('This may take up to a minute for large files',
                                style: TextStyle(fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.5))),
                          ],
                        ),
                      )
                    : Markdown(
                        data: _result,
                        padding: const EdgeInsets.all(16),
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                      ),
          ),
        ],
      ),
    );
  }
}
