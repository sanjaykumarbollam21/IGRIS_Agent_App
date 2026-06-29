import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:igris_mobile/providers/data_providers.dart';
import 'package:igris_mobile/services/voice_service.dart';
import 'package:igris_mobile/services/ai_service.dart';
import 'package:igris_mobile/screens/ai/image_gen_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceTab extends ConsumerStatefulWidget {
  const VoiceTab({super.key});

  @override
  ConsumerState<VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends ConsumerState<VoiceTab>
    with SingleTickerProviderStateMixin {
  final _voice = VoiceService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isProcessing = false;
  bool _micReady = false;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _initMic();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _pulseCtrl.dispose();
    _voice.stop();
    super.dispose();
  }

  Future<void> _initMic() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      await _voice.initialize();
      if (mounted) setState(() => _micReady = _voice.isAvailable);
    }
    // Also request contacts & phone permissions
    await Permission.contacts.request();
    await Permission.phone.request();
  }

  void _scroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
    ));
  }

  // ── MIC TOGGLE ──
  Future<void> _toggleMic() async {
    if (_voice.isListening) {
      // Stop listening
      await _voice.stopListening();
      if (mounted) setState(() {});
      return;
    }

    if (!_micReady) {
      await _initMic();
      if (!_micReady) {
        _snack('Microphone not available. Check app permissions.');
        return;
      }
    }

    setState(() {}); // Update UI to show listening

    try {
      final result = await _voice.startListening();
      if (!mounted) return;
      setState(() {});

      final text = result['transcription'] ?? '';
      if (text.isEmpty) {
        _snack(result['error'] ?? 'No speech detected. Try again.');
        return;
      }

      _addMsg(text, true);
      await _process(text, speak: true);
    } catch (e) {
      if (mounted) {
        setState(() {});
        _snack('Voice error. Please try again.');
      }
    }
  }

  Future<void> _submitText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isProcessing) return;
    
    // Stop any current speech when user starts a text interaction
    await _voice.stopSpeaking();
    
    _textCtrl.clear();
    _addMsg(text, true);
    await _process(text, speak: false);
  }

  Future<void> _process(String text, {bool speak = false}) async {
    setState(() => _isProcessing = true);
    try {
      final result = await _voice.processCommand(text);
      final response = result['response'] ?? 'No response.';
      _addMsg(response, false);

      // Handle navigation signals from VoiceService
      if (result['navigate'] == 'image_gen' && mounted) {
        final prompt = result['prompt'] as String? ?? '';
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImageGenScreen(initialPrompt: prompt),
            ),
          );
        }
      }

      if (speak) {
        try { await _voice.speakResponse(response); } catch (_) {}
      }
    } catch (e) {
      _addMsg('Error processing request.', false);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _addMsg(String text, bool isUser) {
    ref.read(chatProvider.notifier).addMessage(text, isUser: isUser);
    _scroll();
  }

  Future<void> _showHistory() async {
    final ai = AiService();
    final sessions = await ai.getSessions();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Chat History',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(),
            Expanded(
              child: sessions.isEmpty
                  ? const Center(child: Text('No past conversations found'))
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (_, i) {
                        final s = sessions[i];
                        final date = DateTime.tryParse(s['lastMessageAt'] ?? '')
                                ?.toLocal() ??
                            DateTime.now();
                        final sessionId = s['sessionId'];

                        return ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.history)),
                          title: Text(s['firstMessage'] ?? 'New Chat',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${s['messageCount']} messages • ${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () async {
                              final nav = Navigator.of(ctx);
                              final ok = await ai.deleteSession(sessionId);
                              if (ok) {
                                nav.pop();
                                _showHistory(); // Refresh
                              }
                            },
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            setState(() => _isProcessing = true);
                            final msgs = await ai.getSessionMessages(sessionId);
                            if (mounted) {
                              final chatMsgs = msgs
                                  .map((m) => ChatMessage(
                                        text: m['content'] ?? '',
                                        isUser: m['role'] == 'user',
                                        timestamp: DateTime.tryParse(
                                                m['createdAt'] ?? '') ??
                                            DateTime.now(),
                                      ))
                                  .toList();
                              ref
                                  .read(chatProvider.notifier)
                                  .loadSession(sessionId, chatMsgs);
                              setState(() => _isProcessing = false);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final cs = Theme.of(context).colorScheme;
    final listening = _voice.isListening;

    return Column(
      children: [
        // Header with New Chat & History
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text('IGRIS Chat',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  ref.read(chatProvider.notifier).newChat();
                  _snack('New chat started');
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _showHistory,
                icon: const Icon(Icons.history, size: 20),
                tooltip: 'History',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Messages
        Expanded(
          child: messages.isEmpty
              ? _emptyState(cs)
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _bubble(messages[i], cs),
                ),
        ),

        // Listening indicator
        if (listening)
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.error.withValues(
                          alpha: 0.4 + _pulseCtrl.value * 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Listening... Tap mic to stop',
                      style: TextStyle(
                          color: cs.error, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),

        // Processing indicator
        if (_isProcessing && !listening)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                ),
                const SizedBox(width: 8),
                Text('IGRIS is thinking...',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),

        // Input bar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(
                top: BorderSide(color: cs.onSurface.withValues(alpha: 0.1))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SafeArea(
            child: Row(
              children: [
                // Mic toggle button
                GestureDetector(
                  onTap: _isProcessing ? null : _toggleMic,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listening ? cs.error : cs.primary,
                      boxShadow: listening
                          ? [BoxShadow(
                              color: cs.error.withValues(alpha: 0.4),
                              blurRadius: 12, spreadRadius: 2)]
                          : null,
                    ),
                    child: Icon(
                      listening ? Icons.stop : Icons.mic,
                      color: Colors.white, size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Text input
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: InputDecoration(
                      hintText: listening
                          ? 'Listening...'
                          : 'Ask IGRIS anything...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: cs.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitText(),
                    enabled: !listening,
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                IconButton(
                  onPressed: _isProcessing || listening ? null : _submitText,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primary.withValues(alpha: 0.1),
                    foregroundColor: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withValues(alpha: 0.6)],
                ),
              ),
              child: const Icon(Icons.mic, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('Hey, I\'m IGRIS',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Your AI assistant. Ask anything or give a command.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8, runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _cmdChip('Generate an image of a sunset', cs),
                _cmdChip('Search latest AI news', cs),
                _cmdChip('Directions to nearest hospital', cs),
                _cmdChip('Lock laptop', cs),
                _cmdChip('Explain quantum computing', cs),
                _cmdChip('Send message to Mom', cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cmdChip(String text, ColorScheme cs) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      backgroundColor: cs.primary.withValues(alpha: 0.08),
      side: BorderSide(color: cs.primary.withValues(alpha: 0.2)),
      onPressed: () {
        _addMsg(text, true);
        _process(text, speak: false);
      },
    );
  }

  Widget _bubble(ChatMessage msg, ColorScheme cs) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser
                ? const Radius.circular(16)
                : const Radius.circular(4),
            bottomRight: isUser
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('IGRIS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.primary)),
              ),
            SelectableText(msg.text,
                style: TextStyle(
                    color: isUser ? cs.onPrimary : cs.onSurface)),
            const SizedBox(height: 4),
            Text(
              '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 10,
                  color: isUser
                      ? cs.onPrimary.withValues(alpha: 0.7)
                      : cs.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}