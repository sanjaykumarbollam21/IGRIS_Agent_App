import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class CalendarService {
  static final CalendarService _i = CalendarService._();
  factory CalendarService() => _i;
  CalendarService._();

  final Dio _dio = Dio();
  String get _base => '${ConfigurationService().backendUrl}/calendar';

  Future<Options> _auth() async {
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: 'auth_token');
    final geminiKey = await secureStorage.read(key: 'gemini_api_key');
    return Options(headers: {
      'Authorization': 'Bearer ${token ?? ''}',
      if (geminiKey != null && geminiKey.isNotEmpty) 'X-Gemini-API-Key': geminiKey,
    });
  }

  Future<bool> isConnected() async {
    final r = await _dio.get('$_base/status', options: await _auth());
    return r.data['connected'] as bool? ?? false;
  }

  Future<String> getAuthUrl() async {
    final r = await _dio.get('$_base/auth-url', options: await _auth());
    return r.data['authUrl'] as String;
  }

  Future<void> disconnect() async {
    await _dio.delete('$_base/disconnect', options: await _auth());
  }

  Future<Map<String, dynamic>> getEvents({int days = 14, int max = 30}) async {
    final r = await _dio.get('$_base/events',
        queryParameters: {'days': days, 'maxResults': max},
        options: await _auth());
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> createEvent({
    required String title,
    required String start,
    String? end,
    String? description,
    String? location,
    bool isAllDay = false,
  }) async {
    final r = await _dio.post('$_base/events',
        data: {
          'title': title,
          'start': start,
          'end': end ?? start,
          'description': description,
          'location': location,
          'isAllDay': isAllDay,
        },
        options: await _auth());
    return Map<String, dynamic>.from(r.data['event']);
  }

  Future<Map<String, dynamic>> parseNaturalLanguage(String text) async {
    final r = await _dio.post('$_base/events/parse',
        data: {'text': text}, options: await _auth());
    return Map<String, dynamic>.from(r.data['event']);
  }

  Future<void> deleteEvent(String eventId) async {
    await _dio.delete('$_base/events/$eventId', options: await _auth());
  }
}
