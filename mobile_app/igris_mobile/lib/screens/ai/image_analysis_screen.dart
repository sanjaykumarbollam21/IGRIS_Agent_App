import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:igris_mobile/services/ai_service.dart';

class ImageAnalysisScreen extends StatefulWidget {
  const ImageAnalysisScreen({super.key});

  @override
  State<ImageAnalysisScreen> createState() => _ImageAnalysisScreenState();
}

class _ImageAnalysisScreenState extends State<ImageAnalysisScreen> {
  final _ai = AiService();
  final _picker = ImagePicker();
  File? _image;
  Uint8List? _imageBytes;
  String _result = '';
  bool _loading = false;
  String _selectedTask = 'Describe this image in detail.';

  static const _tasks = {
    'Describe': 'Describe this image in detail.',
    'Extract Text': 'Extract all visible text from this image. Format it cleanly.',
    'Translate': 'Extract all text from this image and translate it to English.',
    'Summarize': 'Provide a concise summary of what this image shows.',
    'Analyze Data': 'If this image contains charts, tables, or graphs, extract and explain the data.',
  };

  Future<void> _pickImage(ImageSource source) async {
    final xfile = await _picker.pickImage(
        source: source, maxWidth: 1920, imageQuality: 85);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    setState(() {
      _image = File(xfile.path);
      _imageBytes = bytes;
      _result = '';
    });
  }

  Future<void> _analyze() async {
    if (_imageBytes == null) return;
    setState(() { _loading = true; _result = ''; });
    try {
      final text = await _ai.analyzeImage(_imageBytes!, _selectedTask);
      setState(() => _result = text);
    } catch (e) {
      setState(() => _result = 'Error: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyze Image'),
        actions: [
          if (_result.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.share(_result),
              tooltip: 'Share result',
            ),
        ],
      ),
      body: Column(
        children: [
          // Image preview
          Expanded(
            flex: 4,
            child: _image == null
                ? _emptyState(cs)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_image!, fit: BoxFit.contain),
                      Positioned(
                        bottom: 8, right: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _fabSmall(Icons.photo_library, () => _pickImage(ImageSource.gallery), cs),
                            const SizedBox(width: 8),
                            _fabSmall(Icons.camera_alt, () => _pickImage(ImageSource.camera), cs),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          // Task selector + Analyze button
          Container(
            padding: const EdgeInsets.all(16),
            color: cs.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedTask,
                  decoration: InputDecoration(
                    labelText: 'Analysis Type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: _tasks.entries
                      .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTask = v!),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (_imageBytes == null || _loading) ? null : _analyze,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_loading ? 'Analyzing...' : 'Analyze with Gemini'),
                ),
              ],
            ),
          ),

          // Result
          if (_result.isNotEmpty)
            Expanded(
              flex: 3,
              child: Container(
                color: cs.surface,
                child: Markdown(
                  data: _result,
                  padding: const EdgeInsets.all(16),
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 64,
              color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Pick an image to analyze',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fabSmall(IconData icon, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
