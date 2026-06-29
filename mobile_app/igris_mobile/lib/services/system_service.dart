import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class SystemService {
  final Dio _dio = Dio();
  final _secureStorage = const FlutterSecureStorage();

  SystemService() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = '${ConfigurationService().backendUrl}/system';
          return handler.next(options);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _headers() async {
    final token = await _secureStorage.read(key: 'auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get connected device status (laptop info)
  Future<Map<String, dynamic>> getDeviceStatus() async {
    try {
      final response = await _dio.get('/status',
          options: Options(headers: await _headers()));
      return response.data;
    } catch (e) {
      return {'success': false, 'message': 'Device not reachable: $e'};
    }
  }

  /// Send command to connected device
  Future<Map<String, dynamic>> sendCommand(String action,
      {Map<String, dynamic>? params}) async {
    try {
      final response = await _dio.post('/command',
          data: {'action': action, if (params != null) 'params': params},
          options: Options(headers: await _headers()));
      return response.data;
    } catch (e) {
      return {'success': false, 'message': 'Command failed: $e'};
    }
  }
}
