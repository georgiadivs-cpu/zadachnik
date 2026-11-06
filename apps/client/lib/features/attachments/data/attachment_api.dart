import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../domain/attachment.dart';

class RemoteAttachment {
  const RemoteAttachment({
    required this.id,
    required this.revision,
    required this.sha256,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String id;
  final int revision;
  final String sha256;
  final int sizeBytes;
  final String mimeType;
}

class AttachmentApiFailure implements Exception {
  const AttachmentApiFailure({
    required this.code,
    required this.message,
    this.network = false,
    this.unauthorized = false,
  });

  final String code;
  final String message;
  final bool network;
  final bool unauthorized;
}

abstract interface class AttachmentApi {
  Future<RemoteAttachment> upload({
    required String accessToken,
    required String attachmentId,
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String localPath,
    required String fileName,
    required String mimeType,
  });

  Future<List<int>> download({
    required String accessToken,
    required String attachmentId,
  });

  Future<void> delete({
    required String accessToken,
    required String attachmentId,
  });
}

class DioAttachmentApi implements AttachmentApi {
  DioAttachmentApi({String baseUrl = apiBaseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$baseUrl/api/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  @override
  Future<RemoteAttachment> upload({
    required String accessToken,
    required String attachmentId,
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String localPath,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      final file = await MultipartFile.fromFile(
        localPath,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );
      final form = FormData.fromMap({
        'ownerType': ownerType.wire,
        'ownerId': ownerId,
        'file': file,
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/attachments/$attachmentId',
        data: form,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data ?? const {};
      return RemoteAttachment(
        id: data['id'] as String,
        revision: (data['revision'] as num).toInt(),
        sha256: data['sha256'] as String,
        sizeBytes: (data['sizeBytes'] as num).toInt(),
        mimeType: data['mimeType'] as String,
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<int>> download({
    required String accessToken,
    required String attachmentId,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        '/attachments/$attachmentId',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
      return response.data ?? const [];
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> delete({
    required String accessToken,
    required String attachmentId,
  }) async {
    try {
      await _dio.delete<void>(
        '/attachments/$attachmentId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static AttachmentApiFailure _failure(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return const AttachmentApiFailure(
        code: 'UNAUTHORIZED',
        message: 'Сессия истекла',
        unauthorized: true,
      );
    }
    if (error.response == null) {
      return const AttachmentApiFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер недоступен',
        network: true,
      );
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final body = data['error'];
      if (body is Map<String, dynamic>) {
        return AttachmentApiFailure(
          code: body['code'] as String? ?? 'ATTACHMENT_ERROR',
          message: body['message'] as String? ?? 'Ошибка вложения',
        );
      }
    }
    return AttachmentApiFailure(
      code: 'HTTP_$status',
      message: 'Ошибка вложения ($status)',
    );
  }
}
