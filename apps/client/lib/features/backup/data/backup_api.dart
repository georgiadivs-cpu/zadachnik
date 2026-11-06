import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../domain/backup_models.dart';

class BackupFailure implements Exception {
  const BackupFailure({
    required this.code,
    required this.message,
    this.network = false,
    this.unauthorized = false,
  });

  final String code;
  final String message;
  final bool network;
  final bool unauthorized;

  @override
  String toString() => message;
}

abstract interface class BackupApi {
  Future<BackupStatusSnapshot> status({required String accessToken});

  Future<BackupStatusSnapshot> start({required String accessToken});

  Future<BackupArchiveView> verify({
    required String accessToken,
    required String archiveId,
  });

  Future<BackupSnapshotView> uploadDeviceSnapshot({
    required String accessToken,
    required String localPath,
    required String sha256,
    required int schemaVersion,
  });
}

class DioBackupApi implements BackupApi {
  DioBackupApi({String baseUrl = apiBaseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$baseUrl/api/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  @override
  Future<BackupStatusSnapshot> status({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/backups/status',
        options: _auth(accessToken),
      );
      return BackupStatusSnapshot.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<BackupStatusSnapshot> start({required String accessToken}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/backups',
        options: _auth(accessToken),
      );
      return BackupStatusSnapshot.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<BackupArchiveView> verify({
    required String accessToken,
    required String archiveId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/backups/$archiveId/verify',
        options: _auth(accessToken)
            .copyWith(receiveTimeout: const Duration(minutes: 10)),
      );
      return BackupArchiveView.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<BackupSnapshotView> uploadDeviceSnapshot({
    required String accessToken,
    required String localPath,
    required String sha256,
    required int schemaVersion,
  }) async {
    try {
      final form = FormData.fromMap({
        'sha256': sha256,
        'schemaVersion': schemaVersion,
        'file': await MultipartFile.fromFile(
          localPath,
          filename: 'snapshot.db',
          contentType: DioMediaType('application', 'octet-stream'),
        ),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/backups/devices',
        data: form,
        options: _auth(accessToken).copyWith(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      return BackupSnapshotView.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static Options _auth(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  static BackupFailure _failure(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return const BackupFailure(
        code: 'UNAUTHORIZED',
        message: 'Сессия истекла',
        unauthorized: true,
      );
    }
    if (error.response == null) {
      return const BackupFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер резервных копий недоступен',
        network: true,
      );
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final body = data['error'];
      if (body is Map<String, dynamic>) {
        return BackupFailure(
          code: body['code'] as String? ?? 'BACKUP_ERROR',
          message:
              body['message'] as String? ?? 'Ошибка резервного копирования',
        );
      }
    }
    return BackupFailure(
      code: 'HTTP_$status',
      message: 'Ошибка резервного копирования ($status)',
    );
  }
}
