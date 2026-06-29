import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/screens/ai/image_analysis_screen.dart';
import 'package:igris_mobile/screens/ai/image_gen_screen.dart';
import 'package:igris_mobile/screens/ai/web_search_screen.dart';
import 'package:igris_mobile/screens/ai/audio_transcribe_screen.dart';
import 'package:igris_mobile/screens/ai/video_analysis_screen.dart';
import 'package:igris_mobile/screens/tools/maps_screen.dart';
import 'package:igris_mobile/screens/tools/calendar_screen.dart';
import 'package:igris_mobile/screens/tools/task_manager_screen.dart';

class AiTab extends ConsumerWidget {
  const AiTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget screen) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));

    void soon(String name) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name — coming soon'), behavior: SnackBarBehavior.floating));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('AI Capabilities',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            _techBadge(context, '🤖 Ollama', const Color(0xFF6C63FF)),
            _techBadge(context, '🔍 DuckDuckGo', const Color(0xFF2196F3)),
            _techBadge(context, '🎤 Whisper STT', const Color(0xFF4CAF50)),
            _techBadge(context, '🔊 Edge TTS', const Color(0xFFFF9800)),
          ],
        ),
        const SizedBox(height: 20),

        _label(context, '🖼️  Vision & Image'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _card(context, Icons.image_outlined, 'Generate Image',
              'Text → image', const Color(0xFF6C63FF), () => go(const ImageGenScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.camera_alt_outlined, 'Analyze Image',
              'Describe a photo', const Color(0xFF00BCD4), () => go(const ImageAnalysisScreen()))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _card(context, Icons.edit_outlined, 'Edit Image',
              'Modify with AI', const Color(0xFF4CAF50), () => soon('Image Edit'))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.translate, 'Translate Image',
              'OCR + translate', const Color(0xFFFF9800), () => go(const ImageAnalysisScreen()))),
        ]),

        const SizedBox(height: 20),
        _label(context, '🎬  Video & Audio'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _card(context, Icons.video_library_outlined, 'Analyze Video',
              'Summarize & extract', const Color(0xFFE91E63), () => go(const VideoAnalysisScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.graphic_eq, 'Transcribe Audio',
              'Speech → text', const Color(0xFF9C27B0), () => go(const AudioTranscribeScreen()))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _card(context, Icons.video_call_outlined, 'Generate Video',
              'Text → short video', const Color(0xFF795548), () => soon('Video Generation'))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.music_note_outlined, 'Generate Music',
              'AI music creation', const Color(0xFF009688), () => soon('Music Generation'))),
        ]),

        const SizedBox(height: 20),
        _label(context, '🔍  Search & Navigation'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _card(context, Icons.search, 'Web Search',
              'DuckDuckGo · Real-time', const Color(0xFF2196F3), () => go(const WebSearchScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.map_outlined, 'Maps & Routes',
              'Directions & places', const Color(0xFF4CAF50), () => go(const MapsScreen()))),
        ]),

        const SizedBox(height: 20),
        _label(context, '📅  Productivity'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _card(context, Icons.calendar_month, 'Calendar',
              'View & create events', const Color(0xFF3F51B5), () => go(const CalendarScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _card(context, Icons.task_alt, 'Task Manager',
              'To-dos & reminders', const Color(0xFF009688), () => go(const TaskManagerScreen()))),
        ]),

        const SizedBox(height: 20),
        _label(context, '🧠  Intelligence'),
        const SizedBox(height: 10),
        _wideTile(context, Icons.psychology_outlined, 'Deep Reasoning',
            'Ollama · Llama 3.1 / Mistral / Phi-3', const Color(0xFF6C63FF),
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Use the Voice tab — say "Think deeply about..."'),
                behavior: SnackBarBehavior.floating))),
        const SizedBox(height: 10),
        _wideTile(context, Icons.history_edu_outlined, 'Context-Aware Chat',
            'Multi-turn memory · Playwright automation', const Color(0xFF00BCD4),
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Tap the Voice tab to start chatting with IGRIS'),
                behavior: SnackBarBehavior.floating))),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600));

  Widget _techBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }

  Widget _card(BuildContext context, IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.55)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _wideTile(BuildContext context, IconData icon, String title,
      String subtitle, Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14,
                color: cs.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
