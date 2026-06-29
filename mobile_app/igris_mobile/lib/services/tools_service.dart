import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class ToolsService {
  final Dio _dio = Dio();

  ToolsService() {
    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.baseUrl = '${ConfigurationService().backendUrl}/tools';
          const secureStorage = FlutterSecureStorage();
          final token = await secureStorage.read(key: 'auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> sendMessage({
    required String platform,
    required String recipient,
    required String message,
    String? messageType,
  }) async {
    try {
      final response = await _dio.post(
        '/send-message',
        data: {
          'platform': platform,
          'recipient': recipient,
          'message': message,
          'messageType': messageType,
        },
      );

      return {
        'success': true,
        'result': response.data['result'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _handleDioError(e),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: $e',
      };
    }
  }

  Future<Map<String, dynamic>> openApp({
    required String appName,
    required String appIdentifier,
    String? platform,
  }) async {
    try {
      final response = await _dio.post(
        '/open-app',
        data: {
          'appName': appName,
          'appIdentifier': appIdentifier,
          'platform': platform,
        },
      );

      return {
        'success': true,
        'result': response.data['result'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _handleDioError(e),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: $e',
      };
    }
  }

  Future<Map<String, dynamic>> makeCall({
    required String phoneNumber,
    String? callType,
  }) async {
    try {
      final response = await _dio.post(
        '/make-call',
        data: {
          'phoneNumber': phoneNumber,
          'callType': callType,
        },
      );

      return {
        'success': true,
        'result': response.data['result'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _handleDioError(e),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: $e',
      };
    }
  }

  Future<Map<String, dynamic>> webSearch({
    required String query,
    int? numResults,
  }) async {
    try {
      final response = await _dio.post(
        '/web-search',
        data: {
          'query': query,
          'numResults': numResults,
        },
      );

      return {
        'success': true,
        'result': response.data['result'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _handleDioError(e),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: $e',
      };
    }
  }

  Future<Map<String, dynamic>> fileOperation({
    required String operation,
    required String filePath,
    String? content,
  }) async {
    try {
      final response = await _dio.post(
        '/file-operation',
        data: {
          'operation': operation,
          'filePath': filePath,
          'content': content,
        },
      );

      return {
        'success': true,
        'result': response.data['result'],
        'message': response.data['message'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _handleDioError(e),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error occurred: $e',
      };
    }
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.sendTimeout:
        return 'Request timeout. Please try again.';
      case DioExceptionType.receiveTimeout:
        return 'Response timeout. Please try again.';
      case DioExceptionType.badResponse:
        if (e.response != null && e.response?.data != null) {
          return e.response?.data['message'] ??
              'Server error. Please try again later.';
        }
        return 'Server error. Please try again later.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.unknown:
        return 'Network error. Please check your internet connection.';
      default:
        return 'An unexpected error occurred.';
    }
  }
}