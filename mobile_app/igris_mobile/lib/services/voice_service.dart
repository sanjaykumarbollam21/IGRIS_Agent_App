import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:igris_mobile/services/system_service.dart';
import 'package:igris_mobile/services/configuration_service.dart';
import 'package:igris_mobile/main.dart' show navigatorKey;
import 'package:igris_mobile/widgets/voice/bixby_assistant_overlay.dart';

class VoiceService {
  // Singleton
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final _storage = const FlutterSecureStorage();
  final _systemService = SystemService();
  static const _channel = MethodChannel('com.igris.intents');

  bool _initialized = false;
  bool _sttReady = false;
  bool _isListening = false;

  String _honorific = 'Sir';
  String _userName = '';
  double _rate = 0.45;
  double _pitch = 1.0;

  // Gemini AI via HTTP
  String _geminiKey = '';
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));
  final List<Map<String, dynamic>> _chatContext = [];

  static const _historyKey = 'igris_chat_history';

  // ─── AUTH TOKEN ───
  Future<String?> _getToken() async => await _storage.read(key: 'auth_token');

  // Conversation history (persisted to disk)
  final List<Map<String, String>> _history = [];

  bool get isAvailable => _sttReady;
  bool get isListening => _isListening;
  List<Map<String, String>> get history => List.unmodifiable(_history);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _sttReady = await _stt.initialize(
        onStatus: (_) {},
        onError: (_) {},
      );
    } catch (_) {
      _sttReady = false;
    }

    // Load TTS settings
    _rate = double.tryParse(
            await _storage.read(key: 'voice_speed') ?? '0.45') ??
        0.45;
    _pitch = double.tryParse(
            await _storage.read(key: 'voice_pitch') ?? '1.0') ??
        1.0;

    await _tts.setLanguage('en-US');
    await _tts.setPitch(_pitch);
    await _tts.setSpeechRate(_rate);
    await _tts.setVolume(1.0);

    // Apply saved voice
    final vName = await _storage.read(key: 'voice_name');
    final vLocale = await _storage.read(key: 'voice_locale');
    if (vName != null && vName.isNotEmpty) {
      await _tts.setVoice({'name': vName, 'locale': vLocale ?? 'en-US'});
    }

    await _loadUser();
    await _initGemini();
    await _loadHistory();   // ← restore persisted chat

    // Wire the wake-word handoff so PorcupineWakeWordService can call us
    // with a single .call() and we take care of the rest.
    processWakeWordTrigger = _defaultWakeWordHandler;

    _initialized = true;
  }

  Future<void> _loadUser() async {
    final gender = await _storage.read(key: 'user_gender') ?? 'male';
    _honorific =
        gender == 'female' ? "Ma'am" : gender == 'male' ? 'Sir' : '';
    _userName = await _storage.read(key: 'user_first_name') ?? '';
  }

  Future<void> _initGemini() async {
    final stored = await _storage.read(key: 'gemini_api_key');
    _geminiKey = (stored != null && stored.trim().isNotEmpty) ? stored.trim() : '';
    if (_geminiKey.isNotEmpty) {
      debugPrint('[IGRIS] Custom Gemini key loaded');
    }
  }

  Future<void> reloadSettings() async {
    _initialized = false;
    _chatContext.clear();
    await initialize();
  }

  String _addr([String? name]) {
    final n = name ?? _userName;
    if (_honorific.isEmpty) return n.isNotEmpty ? n : '';
    return n.isNotEmpty ? '$_honorific $n' : _honorific;
  }

  // ─── CONVERSATION HISTORY ───

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _history.clear();
        for (final item in list) {
          if (item is Map) {
            _history.add({
              'role': item['role']?.toString() ?? 'user',
              'text': item['text']?.toString() ?? '',
              'time': item['time']?.toString() ?? '',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[IGRIS] Failed to load chat history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep last 100 messages on disk
      final toSave = _history.length > 100
          ? _history.sublist(_history.length - 100)
          : _history;
      await prefs.setString(_historyKey, jsonEncode(toSave));
    } catch (e) {
      debugPrint('[IGRIS] Failed to save chat history: $e');
    }
  }

  void addToHistory(String role, String text) {
    _history.add({'role': role, 'text': text, 'time': DateTime.now().toIso8601String()});
    // Keep last 50 messages in-memory
    if (_history.length > 50) _history.removeAt(0);
    _saveHistory();  // ← persist after every message
  }

  void clearHistory() {
    _history.clear();
    _chatContext.clear();
    SharedPreferences.getInstance().then((p) => p.remove(_historyKey));
  }

  // ─── STT (toggle mic) ───

  Future<Map<String, dynamic>> startListening({void Function(String)? onPartialResult}) async {
    await initialize();
    if (!_sttReady) {
      return {'transcription': '', 'error': 'Mic not available. Check permissions.'};
    }

    _isListening = true;
    final completer = Completer<Map<String, dynamic>>();
    String words = '';

    try {
      await _stt.listen(
        onResult: (r) {
          words = r.recognizedWords;
          onPartialResult?.call(words);
          if (r.finalResult && !completer.isCompleted) {
            _isListening = false;
            completer.complete({'transcription': words});
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
        ),
      );
    } catch (e) {
      _isListening = false;
      if (!completer.isCompleted) {
        completer.complete({'transcription': '', 'error': '$e'});
      }
    }

    // Safety timeout
    Future.delayed(const Duration(seconds: 32), () {
      if (!completer.isCompleted) {
        _isListening = false;
        _stt.stop();
        completer.complete({
          'transcription': words,
          'error': words.isEmpty ? 'No speech detected' : null,
        });
      }
    });

    return completer.future;
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _stt.stop();
  }

  // ─── WAKE WORD HANDOFF ───────────────────────────────────────────────────
  //
  // Called by the PorcupineWakeWordService when "Hey IGRIS" is detected
  // (either in foreground or via the Android FGS bridge). The implementation:
  //   1. Play a short audible chime so the user knows IGRIS heard them.
  //   2. Capture the *follow-up* utterance (the actual command) via STT.
  //   3. Run that command through the existing processCommand() pipeline.
  //
  // This is intentionally a fire-and-forget Future — the caller (the wake
  // word provider) doesn't await it; the UI is notified via existing
  // history / state mechanisms.

  /// Optional hook the wake word provider can assign. The default
  /// implementation below is wired up by `initialize()` so existing call
  Future<void> Function()? processWakeWordTrigger;

  Future<void> _defaultWakeWordHandler() async {
    try {
      final context = navigatorKey.currentContext;
      if (context != null) {
        showBixbyAssistantOverlay(context);
      } else {
        debugPrint('[IGRIS] navigatorKey.currentContext is null, cannot show Bixby overlay');
      }
    } catch (e) {
      debugPrint('[IGRIS] Wake word handler failed: $e');
      // Don't propagate — the wake word loop should keep listening.
    }
  }

  // ─── PROCESS (local commands first, then AI) ───

  Future<Map<String, dynamic>> processCommand(String text) async {
    await _loadUser();

    // 1. Try local commands (instant, no network)
    final cmd = await _executeCommand(text);
    if (cmd != null) {
      addToHistory('user', text);
      addToHistory('igris', cmd);
      return {'success': true, 'response': cmd};
    }

    // 2. Detect image generation intent — route to Image Gen screen
    final imagePrompt = _extractImagePrompt(text);
    if (imagePrompt != null) {
      final reply = 'Opening image generator for "$imagePrompt", ${_addr()}.';
      addToHistory('user', text);
      addToHistory('igris', reply);
      return {
        'success': true,
        'response': reply,
        'navigate': 'image_gen',       // signal for voice tab
        'prompt': imagePrompt,
      };
    }

    // 3. Use AI (Gemini if key, otherwise Backend → Pollinations fallback)
    if (_geminiKey.isEmpty) {
      return await _askBackend(text);
    }
    return await _askGemini(text);
  }

  /// Returns the image subject if the text is an image generation request.
  String? _extractImagePrompt(String text) {
    final lc = text.toLowerCase().trim();
    final patterns = [
      RegExp(r'(?:generate|create|make|draw|paint|produce)\s+(?:an?\s+)?image\s+(?:of\s+)?(.+)', caseSensitive: false),
      RegExp(r'(?:generate|create|make|draw|paint)\s+(?:a\s+)?(?:picture|photo|illustration|artwork)\s+(?:of\s+)?(.+)', caseSensitive: false),
      RegExp(r'image\s+(?:of|showing)\s+(.+)', caseSensitive: false),
      RegExp(r'show\s+me\s+(?:an?\s+)?(?:image|picture|photo)\s+(?:of\s+)?(.+)', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(lc);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }

  // ─── BACKEND AI (tries backend, falls back to Pollinations.ai) ───
  Future<Map<String, dynamic>> _askBackend(String text) async {
    // 1. Try the IGRIS backend (Supabase / Ollama)
    try {
      final baseUrl = ConfigurationService().backendUrl;
      final token = await _getToken();

      if (token != null) {
        final apiKey = await _storage.read(key: 'gemini_api_key');
        final resp = await _dio.post(
          '$baseUrl/ai/chat',
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              if (apiKey != null && apiKey.trim().isNotEmpty)
                'X-Gemini-API-Key': apiKey.trim(),
            },
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 25),
          ),
          data: jsonEncode({'message': text}),
        );

        if (resp.statusCode == 200) {
          final reply = resp.data['response'] ?? 'No response.';
          addToHistory('igris', reply);
          return {'success': true, 'response': reply};
        }
      }
    } catch (_) {
      // Backend unreachable — fall through to free fallback
    }

    // 2. Free fallback: Pollinations.ai (no API key needed)
    return await _askPollinations(text);
  }

  // ─── POLLINATIONS.AI FREE AI (No key, always available) ───
  Future<Map<String, dynamic>> _askPollinations(String text) async {
    try {
      final systemPrompt = 'You are IGRIS, an intelligent AI assistant. '
          'Address the user as "${_addr()}". Be concise, helpful, and action-oriented. '
          'Keep responses under 3 sentences unless asked for detail.';

      // Build conversation context from history (last 6 messages)
      final historySlice = _history.length > 6
          ? _history.sublist(_history.length - 6)
          : List.of(_history);

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        ...historySlice.map((h) => {
              'role': h['role'] == 'igris' ? 'assistant' : 'user',
              'content': h['text'] ?? '',
            }),
        {'role': 'user', 'content': text},
      ];

      final resp = await _dio.post(
        'https://text.pollinations.ai/',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: jsonEncode({
          'messages': messages,
          'model': 'openai',  // GPT-4o-mini via Pollinations — free
          'private': true,
        }),
      );

      String reply;
      if (resp.statusCode == 200) {
        final data = resp.data;
        if (data is Map) {
          reply = data['choices']?[0]?['message']?['content']?.toString().trim()
              ?? data['text']?.toString().trim()
              ?? 'No response.';
        } else {
          reply = data.toString().trim();
        }
      } else {
        reply = 'AI unavailable right now, ${_addr()}. Check your connection.';
      }

      addToHistory('igris', reply);
      return {'success': true, 'response': reply};
    } catch (e) {
      final fallback = 'Could not reach AI, ${_addr()}. '
          'Make sure you\'re connected to the internet.';
      addToHistory('igris', fallback);
      return {'success': false, 'response': fallback};
    }
  }

  // ─── GEMINI AI (LOCAL) ───

  Future<String?> _executeCommand(String text) async {
    final lc = text.toLowerCase().trim();

    // ── Send message ──
    if (_matchSendMessage(lc)) return _handleSendMessage(lc);

    // ── Call (number or contact name) ──
    if (lc.startsWith('call ') || lc.startsWith('dial ')) {
      final target = lc.replaceFirst(RegExp(r'^(call|dial)\s+'), '').trim();
      if (target.isNotEmpty) {
        final isNum = RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(target);
        if (isNum) {
          try {
            await _channel.invokeMethod('callContact',
                {'number': target.replaceAll(RegExp(r'[^\d\+]'), '')});
            return 'Calling $target, ${_addr()}.';
          } catch (_) {
            await launchUrl(Uri(scheme: 'tel', path: target));
            return 'Dialing $target, ${_addr()}.';
          }
        } else {
          return await _searchAndCall(target);
        }
      }
    }

    // ── Find/search contact ──
    if (lc.startsWith('find ') && !lc.contains('google') && !lc.contains('web')) {
      final name = lc.replaceFirst('find ', '').trim();
      if (name.isNotEmpty) {
        try {
          final results = await _channel.invokeMethod('searchContact', {'name': name});
          if (results is List && results.isNotEmpty) {
            final list = results.map((c) => '${c['name']}: ${c['number']}').join('\n• ');
            return 'Found contacts for "$name", ${_addr()}:\n• $list';
          }
          return 'No contacts found for "$name", ${_addr()}.';
        } catch (_) {
          return 'Could not search contacts, ${_addr()}.';
        }
      }
    }

    // ── WhatsApp ──
    if (lc.contains('whatsapp') && (lc.contains('send') || lc.contains('message'))) {
      return _handleWhatsApp(lc);
    }

    // ── Time ──
    if (lc.contains('what time') || lc.contains('current time') || lc == 'time') {
      final now = DateTime.now();
      final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
      final p = now.hour >= 12 ? 'PM' : 'AM';
      return 'The time is $h:${now.minute.toString().padLeft(2, '0')} $p, ${_addr()}.';
    }

    // ── Date ──
    if (lc.contains('what date') || lc.contains('today') || lc.contains('what day')) {
      final now = DateTime.now();
      final days = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
      final months = ['January','February','March','April','May','June',
        'July','August','September','October','November','December'];
      return 'Today is ${days[now.weekday % 7]}, ${months[now.month-1]} ${now.day}, ${now.year}, ${_addr()}.';
    }

    // ── Attendance / MyNiat ──
    if (lc.contains('attendance') || lc.contains('myniat') || lc.contains('my niat') || lc.contains('niat')) {
      try {
        await _channel.invokeMethod('launchApp', {'package': 'tech.nxtwave.myniat'});
        return 'Opening MyNiat, ${_addr()}.';
      } catch (_) {
        return 'Could not open MyNiat, ${_addr()}.';
      }
    }

    // ── Open app ──
    if (lc.startsWith('open ')) {
      final app = lc.replaceFirst('open ', '').trim();
      // Try camera, clock, settings natively first
      if (app == 'camera') {
        try { await _channel.invokeMethod('openCamera'); return 'Opening camera, ${_addr()}.'; } catch (_) {}
      }
      if (app == 'clock') {
        try { await _channel.invokeMethod('openClock'); return 'Opening clock, ${_addr()}.'; } catch (_) {}
      }
      if (app == 'settings') {
        try { await _channel.invokeMethod('openAppSettings'); return 'Opening settings, ${_addr()}.'; } catch (_) {}
      }

      // Query all installed apps on the device and launch by name!
      try {
        final bool success = await _channel.invokeMethod<bool>('openAppByName', {'name': app}) ?? false;
        if (success) {
          return 'Opening $app, ${_addr()}.';
        }
      } catch (e) {
        debugPrint('[VoiceService] Local openAppByName failed: $e');
      }

      // Fallback to URL maps if not installed on device
      final urls = {
        'youtube': 'https://youtube.com', 'whatsapp': 'https://wa.me',
        'instagram': 'https://instagram.com', 'telegram': 'https://t.me',
        'spotify': 'https://open.spotify.com', 'gmail': 'mailto:',
        'chrome': 'https://google.com', 'maps': 'https://maps.google.com',
        'netflix': 'https://netflix.com', 'twitter': 'https://twitter.com',
        'x': 'https://twitter.com',
        'google play': 'https://play.google.com',
        'play store': 'https://play.google.com',
        'playstore': 'https://play.google.com',
        'google play store': 'https://play.google.com',
      };
      
      final url = urls[app];
      if (url != null) {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return 'Opening $app, ${_addr()}.';
        } catch (_) {}
      }

      return 'Could not open $app, ${_addr()}.';
    }

    // ── Search ──
    if (lc.startsWith('search ') || lc.startsWith('google ')) {
      final q = lc.replaceFirst(RegExp(r'^(search|google)\s+'), '').trim();
      if (q.isNotEmpty) {
        await launchUrl(
            Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(q)}'),
            mode: LaunchMode.externalApplication);
        return 'Searching for "$q", ${_addr()}.';
      }
    }

    // ── Laptop controls ──
    if (lc.contains('laptop') || lc.contains('computer') || lc.contains('pc')) {
      if (lc.contains('shutdown')) { await _systemService.sendCommand('shutdown'); return 'Shutting down laptop, ${_addr()}.'; }
      if (lc.contains('lock')) { await _systemService.sendCommand('lock'); return 'Locking laptop, ${_addr()}.'; }
      if (lc.contains('sleep')) { await _systemService.sendCommand('sleep'); return 'Laptop sleeping, ${_addr()}.'; }
      if (lc.contains('volume up') || lc.contains('increase volume')) { await _systemService.sendCommand('volume_up'); return 'Volume increased, ${_addr()}.'; }
      if (lc.contains('volume down') || lc.contains('decrease volume')) { await _systemService.sendCommand('volume_down'); return 'Volume decreased, ${_addr()}.'; }
      if (lc.contains('mute')) { await _systemService.sendCommand('volume_mute'); return 'Muted laptop, ${_addr()}.'; }
    }

    // ── Greetings ──
    if (lc == 'hi' || lc == 'hello' || lc == 'hey' || lc == 'hey igris' || lc == 'igris') {
      final h = DateTime.now().hour;
      final g = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
      return '$g, ${_addr()}! How can I help you?';
    }

    // ── Who are you ──
    if (lc.contains('who are you') || lc.contains('your name')) {
      return 'I\'m IGRIS, ${_addr()} — your AI assistant. I can make calls, send messages, search contacts, control your laptop, answer questions, and much more.';
    }

    // ── Thank you ──
    if (lc.contains('thank')) return 'You\'re welcome, ${_addr()}!';

    return null; // No local command matched → use Gemini
  }

  // ─── GEMINI AI ───

  Future<Map<String, dynamic>> _askGemini(String text) async {
    addToHistory('user', text);
    try {
      // Reload key each time
      await _initGemini();

      // Build conversation context
      _chatContext.add({'role': 'user', 'parts': [{'text': text}]});

      // Try models in order of preference
      final models = ['gemini-2.0-flash-lite', 'gemini-1.5-flash', 'gemini-pro'];
      
      for (final model in models) {
        final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiKey';

        final body = {
          'contents': _chatContext,
          'systemInstruction': {
            'parts': [{'text': 'You are IGRIS, an intelligent AI assistant. Address the user as "${_addr()}". Be concise, helpful, and action-oriented. Keep responses under 3 sentences unless asked for detail.'}]
          },
          'tools': [
            { 'googleSearch': {} }
          ],
          'generationConfig': {
            'maxOutputTokens': 1024,
            'temperature': 0.7,
          },
        };

        debugPrint('[IGRIS] Trying model: $model');
        try {
          final response = await _dio.post(url,
              data: jsonEncode(body),
              options: Options(
                headers: {'Content-Type': 'application/json'},
                validateStatus: (status) => true, // Don't throw on error codes
              ));

          debugPrint('[IGRIS] Response status: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = response.data;
            final reply = data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString().trim() ?? 'No response from AI.';
            _chatContext.add({'role': 'model', 'parts': [{'text': reply}]});
            if (_chatContext.length > 20) _chatContext.removeRange(0, 2);
            addToHistory('igris', reply);
            return {'success': true, 'response': reply};
          } else if (response.statusCode == 404) {
            debugPrint('[IGRIS] Model $model not found, trying next...');
            continue; // Try next model
          } else {
            // Extract error message
            final errData = response.data;
            final errMsg = errData is Map ? (errData['error']?['message'] ?? errData.toString()) : errData.toString();
            debugPrint('[IGRIS] API error: $errMsg. Falling back to backend AI.');
            if (_chatContext.isNotEmpty) _chatContext.removeLast();
            
            // Fall back to backend / Pollinations
            final fallbackResult = await _askBackend(text);
            if (fallbackResult['success'] == true) {
              final original = fallbackResult['response'] as String;
              final decorated = '$original\n\n(Note: Gemini API key quota exceeded or invalid. Using fallback server.)';
              if (_history.isNotEmpty && _history.last['role'] == 'igris') {
                _history.last['text'] = decorated;
                _saveHistory();
              }
              return {'success': true, 'response': decorated};
            }
            
            return fallbackResult;
          }
        } catch (e) {
          debugPrint('[IGRIS] Network error for $model: $e');
          if (model == models.last) rethrow;
          continue;
        }
      }
      
      if (_chatContext.isNotEmpty) _chatContext.removeLast();
      return await _askBackend(text);
    } catch (e) {
      debugPrint('[IGRIS] Fatal error: $e. Falling back to backend AI.');
      if (_chatContext.isNotEmpty) _chatContext.removeLast();
      
      final fallbackResult = await _askBackend(text);
      if (fallbackResult['success'] == true) {
        return fallbackResult;
      }
      
      final fallback = 'Could not reach AI, ${_addr()}. Check your internet connection.';
      addToHistory('igris', fallback);
      return {'success': false, 'response': fallback};
    }
  }

  // ─── SEND MESSAGE HANDLER ───

  bool _matchSendMessage(String lc) {
    return lc.startsWith('send message') ||
        lc.startsWith('send a message') ||
        lc.startsWith('message ') ||
        lc.startsWith('text ') ||
        lc.startsWith('sms ');
  }

  Future<String> _handleSendMessage(String lc) async {
    String target = '';
    String body = '';

    final sayingMatch = RegExp(
            r'(?:send\s+(?:a\s+)?message|text|sms)\s+(?:to\s+)?(.+?)\s+(?:saying|that|with message)\s+(.+)',
            caseSensitive: false)
        .firstMatch(lc);
    if (sayingMatch != null) {
      target = sayingMatch.group(1)!.trim();
      body = sayingMatch.group(2)!.trim();
    } else {
      final toMatch = RegExp(
              r'(?:send\s+(?:a\s+)?message|text|sms)\s+(?:to\s+)?(.+)',
              caseSensitive: false)
          .firstMatch(lc);
      if (toMatch != null) target = toMatch.group(1)!.trim();
    }

    // If target is a name (not number), search contacts
    if (target.isNotEmpty && !RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(target)) {
      try {
        final results = await _channel.invokeMethod('searchContact', {'name': target});
        if (results is List && results.isNotEmpty) {
          final number = results.first['number'] ?? '';
          final name = results.first['name'] ?? target;
          if (number.isNotEmpty) {
            final uri = Uri(scheme: 'sms', path: number,
                queryParameters: body.isNotEmpty ? {'body': body} : null);
            await launchUrl(uri);
            return body.isNotEmpty
                ? 'Sending "$body" to $name, ${_addr()}.'
                : 'Opening message to $name, ${_addr()}.';
          }
        }
      } catch (_) {}
    }

    if (target.isEmpty) {
      await launchUrl(Uri(scheme: 'sms', path: ''));
      return 'Opening Messages, ${_addr()}.';
    }

    final uri = Uri(scheme: 'sms', path: target,
        queryParameters: body.isNotEmpty ? {'body': body} : null);
    await launchUrl(uri);
    return body.isNotEmpty
        ? 'Sending "$body" to $target, ${_addr()}.'
        : 'Opening message to $target, ${_addr()}.';
  }

  Future<String> _handleWhatsApp(String lc) async {
    final match = RegExp(r'whatsapp.*?(?:to\s+)?(\d{10,})\s*(?:saying\s+)?(.*)').firstMatch(lc);
    if (match != null) {
      final number = match.group(1)!;
      final msg = match.group(2)?.trim() ?? '';
      final url = 'https://wa.me/$number${msg.isNotEmpty ? '?text=${Uri.encodeComponent(msg)}' : ''}';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return 'Opening WhatsApp for $number, ${_addr()}.';
    }
    await launchUrl(Uri.parse('https://wa.me'), mode: LaunchMode.externalApplication);
    return 'Opening WhatsApp, ${_addr()}.';
  }

  // ─── CONTACT SEARCH + CALL ───

  Future<String> _searchAndCall(String name) async {
    try {
      final results = await _channel.invokeMethod('searchContact', {'name': name});
      if (results is List && results.isNotEmpty) {
        final cName = results.first['name'] ?? name;
        final cNumber = results.first['number'] ?? '';
        if (cNumber.isNotEmpty) {
          try {
            await _channel.invokeMethod('callContact', {'number': cNumber});
            return 'Calling $cName, ${_addr()}.';
          } catch (_) {
            await launchUrl(Uri(scheme: 'tel', path: cNumber));
            return 'Dialing $cName, ${_addr()}.';
          }
        }
      }
      return 'No contact found for "$name", ${_addr()}.';
    } catch (_) {
      return 'Could not search contacts, ${_addr()}.';
    }
  }

  // ─── TTS ───

  Future<void> speakResponse(String text) async {
    await initialize();
    final clean = text
        .replaceAll('•', '')
        .replaceAll('\n', '. ')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.length > 500) {
      await _tts.speak(clean.substring(0, 500));
    } else {
      await _tts.speak(clean);
    }
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  Future<void> stop() async {
    _isListening = false;
    await _stt.stop();
    await _tts.stop();
  }

  Future<List<Map<String, String>>> getAvailableVoices() async {
    await initialize();
    final voices = await _tts.getVoices;
    if (voices == null) return [];
    return (voices as List)
        .where((v) => v['locale']?.toString().startsWith('en') == true)
        .map<Map<String, String>>((v) => {
              'name': v['name']?.toString() ?? '',
              'locale': v['locale']?.toString() ?? '',
            })
        .toList();
  }

  Future<void> setVoice(String name, String locale) async {
    await _tts.setVoice({'name': name, 'locale': locale});
    await _storage.write(key: 'voice_name', value: name);
    await _storage.write(key: 'voice_locale', value: locale);
  }
}