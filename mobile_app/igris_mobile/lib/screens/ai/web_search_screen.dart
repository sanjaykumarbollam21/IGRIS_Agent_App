import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:igris_mobile/services/ai_service.dart';

class WebSearchScreen extends StatefulWidget {
  const WebSearchScreen({super.key});

  @override
  State<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends State<WebSearchScreen> {
  final _ai = AiService();
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String _aiSummary = '';
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _results = []; _aiSummary = ''; _error = null; });

    try {
      final result = await _ai.webSearch(q);
      if (result['success'] == true) {
        final items = result['result']?['items'] as List? ?? [];
        final summary = result['result']?['aiSummary'] as String? ?? '';
        setState(() {
          _results = items.cast<Map<String, dynamic>>();
          _aiSummary = summary;
        });
      } else {
        setState(() => _error = result['error'] ?? 'Search failed');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Web Search')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              controller: _ctrl,
              hintText: 'Search anything...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(icon: const Icon(Icons.send), onPressed: _search),
              ],
              onSubmitted: (_) => _search(),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // AI summary card
                if (_aiSummary.isNotEmpty) ...[
                  Card(
                    color: cs.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.auto_awesome, size: 16, color: cs.onPrimaryContainer),
                            const SizedBox(width: 6),
                            Text('IGRIS Summary', style: TextStyle(
                                fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
                          ]),
                          const SizedBox(height: 8),
                          MarkdownBody(data: _aiSummary,
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Search results
                ..._results.map((r) => _resultCard(r, cs)),

                if (!_loading && _results.isEmpty && _aiSummary.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(Icons.travel_explore, size: 64,
                              color: cs.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text('Search the web with AI',
                              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final url = r['link'] as String?;
          if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r['title'] ?? '',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(r['link'] ?? '',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (r['snippet'] != null) ...[
                const SizedBox(height: 6),
                Text(r['snippet'],
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
