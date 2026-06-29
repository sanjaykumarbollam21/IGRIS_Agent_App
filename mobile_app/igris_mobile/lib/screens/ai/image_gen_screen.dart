import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:igris_mobile/services/ai_service.dart';
import 'package:igris_mobile/providers/data_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImageGenScreen extends ConsumerStatefulWidget {
  final String? initialPrompt;
  const ImageGenScreen({super.key, this.initialPrompt});

  @override
  ConsumerState<ImageGenScreen> createState() => _ImageGenScreenState();
}

class _ImageGenScreenState extends ConsumerState<ImageGenScreen> {
  final _ai = AiService();
  final _promptCtrl = TextEditingController();
  String _aspectRatio = '1:1';
  String _style = 'photorealistic';
  bool _loading = false;
  Uint8List? _generatedImage;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      _promptCtrl.text = widget.initialPrompt!;
      // Auto-generate after frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  static const _aspects = ['1:1', '16:9', '9:16', '4:3', '3:4'];
  static const _styles = {
    'photorealistic': Icons.photo_camera,
    'anime': Icons.face_retouching_natural,
    'painting': Icons.palette,
    'digital_art': Icons.computer,
    'sketch': Icons.draw,
  };

  static const _prompts = [
    'A futuristic city at night with neon lights',
    'Peaceful Japanese zen garden at sunrise',
    'Astronaut surfing on Saturn\'s rings',
    'Cyberpunk samurai in a rainy alley',
    'Cozy cottage in a magical forest',
  ];

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;
    setState(() { _loading = true; _generatedImage = null; _errorMsg = null; });

    try {
      final result = await _ai.generateImage(
        prompt: prompt,
        aspectRatio: _aspectRatio,
        style: _style,
      );

      if (result['success'] == true) {
        // Backend returns base64 image data
        final b64 = result['imageData'] as String?;
        if (b64 != null) {
          setState(() => _generatedImage = base64Decode(b64));
          ref.read(dashboardStatsProvider.notifier).incrementImage();
        } else {
          setState(() => _errorMsg = 'No image data returned.');
        }
      } else {
        setState(() => _errorMsg = result['error'] ?? 'Generation failed.');
      }
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveImage() async {
    if (_generatedImage == null) return;
    try {
      // Request permission first (Android 13+ needs READ_MEDIA_IMAGES)
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) await Gal.requestAccess(toAlbum: true);

      // Save directly to device gallery (DCIM/Pictures)
      await Gal.putImageBytes(_generatedImage!, album: 'IGRIS');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Saved to Gallery → IGRIS album'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Image'),
        actions: [
          if (_generatedImage != null) ...[
            IconButton(icon: const Icon(Icons.save_alt), onPressed: _saveImage, tooltip: 'Save'),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () async {
                final dir = await getTemporaryDirectory();
                final file = File('${dir.path}/igris_share.jpg');
                await file.writeAsBytes(_generatedImage!);
                await Share.shareXFiles([XFile(file.path)], text: _promptCtrl.text);
              },
              tooltip: 'Share',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Image preview area
          Expanded(
            child: _loading
                ? _loadingView(cs)
                : _generatedImage != null
                    ? InteractiveViewer(child: Image.memory(_generatedImage!, fit: BoxFit.contain))
                    : _placeholderView(cs),
          ),

          // Error
          if (_errorMsg != null)
            Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(_errorMsg!, style: TextStyle(color: cs.onErrorContainer)),
            ),

          // Controls
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
            ),
            child: Column(
              children: [
                // Prompt input
                TextField(
                  controller: _promptCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Describe the image you want to create...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),

                // Aspect ratio chips
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _aspects.map((a) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(a, style: const TextStyle(fontSize: 12)),
                        selected: _aspectRatio == a,
                        onSelected: (_) => setState(() => _aspectRatio = a),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // Style selector
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _styles.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(e.value, size: 14),
                        label: Text(_capitalize(e.key), style: const TextStyle(fontSize: 11)),
                        selected: _style == e.key,
                        onSelected: (_) => setState(() => _style = e.key),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                FilledButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_loading ? 'Generating...' : 'Generate'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingView(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60, height: 60,
            child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text('IGRIS is painting...', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _placeholderView(ColorScheme cs) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 72, color: cs.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 20),
            Text('Your generated image will appear here',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text('Try:', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _prompts.map((p) => ActionChip(
                label: Text(p, style: const TextStyle(fontSize: 11)),
                onPressed: () { _promptCtrl.text = p; },
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ') : s;
}
