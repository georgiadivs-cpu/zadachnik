import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import 'auth_models.dart';

class AuthFailure implements Exception {
  const AuthFailure({
    required this.code,
    required this.message,
    this.network = false,
  });

  final String code;
  final String message;
  final bool network;

  factory AuthFailure.fromDio(DioException exception) {
    final response = exception.response;
    if (response == null) {
      return const AuthFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер недоступен. Проверьте подключение.',
        network: true,
      );
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        return AuthFailure(
          code: error['code'] as String? ?? 'ERROR',
          message: error['message'] as String? ?? 'Ошибка запроса',
        );
      }
    }

    return AuthFailure(
      code: 'HTTP_${response.statusCode}',
      message: 'Ошибка сервера (${response.statusCode})',
    );
  }

  @override
  String toString() => message;
}

abstract interface class AuthApi {
  Future<AuthResponse> setup({
    required String setupToken,
    required String email,
    required String password,
    required DeviceInfo device,
  });

  Future<AuthResponse> login({
    required String email,
    required String password,
    required DeviceInfo device,
  });

  Future<AuthResponse> refresh(String refreshToken);

  Future<void> logout(String refreshToken);
}

class DioAuthApi implements AuthApi {
  DioAuthApi({String baseUrl = apiBaseUrl, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: '$baseUrl/api/v1',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                contentType: Headers.jsonContentType,
              ),
            );

  final Dio _dio;

  @override
  Future<AuthResponse> setup({
    required String setupToken,
    required String email,
    required String password,
    required DeviceInfo device,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/setup',
        data: {
          'email': email.trim(),
          'password': password,
          'device': device.toJson(),
        },
        options: Options(headers: {'X-Setup-Token': setupToken}),
      );
      return AuthResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    }
  }

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
    required DeviceInfo device,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'device': device.toJson(),
        },
      );
      return AuthResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    }
  }

  @override
  Future<AuthResponse> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return AuthResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    }
  }

  @override
  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post<void>('/auth/logout', data: {'refreshToken': refreshToken});
    } on DioException catch (error) {
      throw AuthFailure.fromDio(error);
    }
  }
}
