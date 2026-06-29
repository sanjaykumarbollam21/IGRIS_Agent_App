import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─── Chat Message Model ───────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? mediaType; // 'image', 'audio', null
  final String? mediaUrl;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.mediaType,
    this.mediaUrl,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'mediaType': mediaType,
        'mediaUrl': mediaUrl,
      };

  factory ChatMessage.fromMap(Map<dynamic, dynamic> map) => ChatMessage(
        text: map['text'] ?? '',
        isUser: map['isUser'] ?? false,
        timestamp: map['timestamp'] != null
            ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
            : DateTime.now(),
        mediaType: map['mediaType'],
        mediaUrl: map['mediaUrl'],
      );
}

// ─── Chat State Notifier with Hive Persistence ───────────────────────────────
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  static const _boxName = 'chat_history_v2';
  Box? _box;
  String? _currentSessionId;

  String? get currentSessionId => _currentSessionId;

  ChatNotifier() : super([]) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    _box = await Hive.openBox(_boxName);
    _currentSessionId = _box?.get('current_session_id');
    if (_currentSessionId == null) {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _box?.put('current_session_id', _currentSessionId);
    }

    final saved = _box?.get('messages_$_currentSessionId', defaultValue: <dynamic>[]);
    if (saved is List && saved.isNotEmpty) {
      state = saved
          .map((m) => ChatMessage.fromMap(m as Map<dynamic, dynamic>))
          .toList();
    }
  }

  void loadSession(String sessionId, List<ChatMessage> messages) {
    _currentSessionId = sessionId;
    state = messages;
    _box?.put('current_session_id', sessionId);
    _saveToStorage();
  }

  void newChat() {
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    state = [];
    _box?.put('current_session_id', _currentSessionId);
  }

  void addMessage(String text, {required bool isUser, String? mediaType, String? mediaUrl}) {
    final updated = [
      ...state,
      ChatMessage(text: text, isUser: isUser, mediaType: mediaType, mediaUrl: mediaUrl),
    ];
    // Keep last 100 messages
    if (updated.length > 100) updated.removeRange(0, updated.length - 100);
    state = updated;
    _saveToStorage();
  }

  Future<void> _saveToStorage() async {
    if (_currentSessionId == null) return;
    _box ??= await Hive.openBox(_boxName);
    await _box?.put('messages_$_currentSessionId', state.map((m) => m.toMap()).toList());
  }

  void clear() {
    state = [];
    _box?.delete('messages');
  }
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier();
});

// ─── Dashboard Stats Model (no attendance) ────────────────────────────────────
class DashboardStats {
  final String userName;
  final int conversationsToday;
  final int toolsUsedToday;
  final int imagesGenerated;
  final bool isLoading;
  final String? error;

  DashboardStats({
    this.userName = 'User',
    this.conversationsToday = 0,
    this.toolsUsedToday = 0,
    this.imagesGenerated = 0,
    this.isLoading = true,
    this.error,
  });

  DashboardStats copyWith({
    String? userName,
    int? conversationsToday,
    int? toolsUsedToday,
    int? imagesGenerated,
    bool? isLoading,
    String? error,
  }) {
    return DashboardStats(
      userName: userName ?? this.userName,
      conversationsToday: conversationsToday ?? this.conversationsToday,
      toolsUsedToday: toolsUsedToday ?? this.toolsUsedToday,
      imagesGenerated: imagesGenerated ?? this.imagesGenerated,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

// ─── Dashboard Stats Notifier ─────────────────────────────────────────────────
class DashboardStatsNotifier extends StateNotifier<DashboardStats> {
  final _secureStorage = const FlutterSecureStorage();

  DashboardStatsNotifier() : super(DashboardStats()) {
    loadStats();
  }

  Future<void> loadStats() async {
    state = state.copyWith(isLoading: true);
    try {
      final firstName = await _secureStorage.read(key: 'user_first_name');
      final email = await _secureStorage.read(key: 'user_email');
      final userName = (firstName != null && firstName.isNotEmpty)
          ? firstName
          : email?.split('@').first ?? 'User';

      // Read local counters from Hive
      Box? statsBox;
      try {
        statsBox = await Hive.openBox('daily_stats');
      } catch (_) {}

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final storedDate = statsBox?.get('date') as String?;
      int conversations = 0;
      int tools = 0;
      int images = 0;

      if (storedDate == today) {
        conversations = (statsBox?.get('conversations') as int?) ?? 0;
        tools = (statsBox?.get('tools') as int?) ?? 0;
        images = (statsBox?.get('images') as int?) ?? 0;
      }

      state = state.copyWith(
        userName: userName,
        conversationsToday: conversations,
        toolsUsedToday: tools,
        imagesGenerated: images,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> incrementConversation() async {
    await _bumpCounter('conversations');
    state = state.copyWith(conversationsToday: state.conversationsToday + 1);
  }

  Future<void> incrementTool() async {
    await _bumpCounter('tools');
    state = state.copyWith(toolsUsedToday: state.toolsUsedToday + 1);
  }

  Future<void> incrementImage() async {
    await _bumpCounter('images');
    state = state.copyWith(imagesGenerated: state.imagesGenerated + 1);
  }

  Future<void> _bumpCounter(String key) async {
    try {
      final box = await Hive.openBox('daily_stats');
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (box.get('date') != today) {
        await box.put('date', today);
        await box.put('conversations', 0);
        await box.put('tools', 0);
        await box.put('images', 0);
      }
      final current = (box.get(key) as int?) ?? 0;
      await box.put(key, current + 1);
    } catch (_) {}
  }

  Future<void> refresh() => loadStats();
}

final dashboardStatsProvider =
    StateNotifierProvider<DashboardStatsNotifier, DashboardStats>((ref) {
  return DashboardStatsNotifier();
});
