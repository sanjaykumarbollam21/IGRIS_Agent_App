import 'package:dio/dio.dart';
import 'package:igris_mobile/models/user_model.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class AuthService {
  final Dio _dio = Dio();

  AuthService() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.options.sendTimeout = const Duration(seconds: 15);

    // Set the base URL once on the Dio instance. Don't reassign it inside the
    // onRequest interceptor — Dio's path-resolution behavior depends on
    // baseUrl being a fixed option, not a per-request header.
    _dio.options.baseUrl = ConfigurationService().backendUrl;

    // Add headers
    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Logging/error interception only — no request mutation.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.next(options),
        onResponse: (response, handler) => handler.next(response),
        onError: (error, handler) => handler.next(error),
      ),
    );
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      return {
        'success': true,
        'token': response.data['token'],
        'refreshToken': response.data['refreshToken'],
        'user': UserModel.fromJson(response.data['user']),
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

  Future<Map<String, dynamic>> register(
      String email,
      String password,
      String firstName,
      String lastName,
      ) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        },
      );

      return {
        'success': true,
        'token': response.data['token'],
        'refreshToken': response.data['refreshToken'],
        'user': UserModel.fromJson(response.data['user']),
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

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        '/auth/refresh-token',
        data: {
          'refreshToken': refreshToken,
        },
      );

      return {
        'success': true,
        'token': response.data['token'],
        'refreshToken': response.data['refreshToken'],
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

  Future<Map<String, dynamic>> logout(String token) async {
    try {
      final response = await _dio.post(
        '/auth/logout',
        data: {},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      return {
        'success': true,
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