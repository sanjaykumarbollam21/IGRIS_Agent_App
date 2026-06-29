import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

/// AutomationService — talks to /api/automations on the IGRIS backend.
/// Supports full CRUD + NLP parsing + manual run.
class AutomationService {
  static final AutomationService _instance = AutomationService._internal();
  factory AutomationService() => _instance;
  AutomationService._internal();

  final Dio _dio = Dio();

  String get _baseUrl => '${ConfigurationService().backendUrl}/automations';

  Future<Options> _authOptions() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token') ?? '';
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ── List all automations ─────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listAutomations() async {
    final opts = await _authOptions();
    final resp = await _dio.get(_baseUrl, options: opts);
    final data = resp.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['automations'] ?? []);
  }

  // ── Create automation ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createAutomation({
    required String name,
    String? description,
    required String triggerType,
    required Map<String, dynamic> triggerConfig,
    required String actionType,
    required Map<String, dynamic> actionConfig,
  }) async {
    final opts = await _authOptions();
    final resp = await _dio.post(_baseUrl,
        data: {
          'name': name,
          'description': description,
          'triggerType': triggerType,
          'triggerConfig': triggerConfig,
          'actionType': actionType,
          'actionConfig': actionConfig,
        },
        options: opts);
    return Map<String, dynamic>.from(resp.data['automation']);
  }

  // ── Toggle active state ──────────────────────────────────────────────────
  Future<bool> toggleAutomation(String id) async {
    final opts = await _authOptions();
    final resp = await _dio.patch('$_baseUrl/$id/toggle', options: opts);
    return resp.data['isActive'] as bool;
  }

  // ── Run automation manually ──────────────────────────────────────────────
  Future<String> runAutomation(String id) async {
    final opts = await _authOptions();
    final resp = await _dio.post('$_baseUrl/$id/run', options: opts);
    return resp.data['result']?.toString() ?? 'Done';
  }

  // ── Delete automation ────────────────────────────────────────────────────
  Future<void> deleteAutomation(String id) async {
    final opts = await _authOptions();
    await _dio.delete('$_baseUrl/$id', options: opts);
  }

  // ── Parse natural language into automation JSON ──────────────────────────
  Future<Map<String, dynamic>> parseNaturalLanguage(String text) async {
    final opts = await _authOptions();
    final resp = await _dio.post('$_baseUrl/parse',
        data: {'text': text}, options: opts);
    return Map<String, dynamic>.from(resp.data['automation']);
  }
}
