import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';

class SyncOperationRequest {
  const SyncOperationRequest({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.clientTimestamp,
    this.baseRevision,
    this.payload,
  });

  final String operationId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'deviceId': deviceId,
    'entityType': entityType,
    'entityId': entityId,
    'operationType': operationType,
    'clientTimestamp': clientTimestamp.toUtc().toIso8601String(),
    if (baseRevision != null) 'baseRevision': baseRevision,
    if (payload != null) 'payload': payload,
  };
}

class PushOutcome {
  const PushOutcome({
    required this.operationId,
    required this.status,
    this.entityId,
    this.revision,
    this.changeSeq,
    this.serverEntity,
    this.code,
    this.message,
  });

  final String operationId;
  final String status;
  final String? entityId;
  final int? revision;
  final int? changeSeq;
  final Map<String, dynamic>? serverEntity;
  final String? code;
  final String? message;
}

class PullChange {
  const PullChange({
    required this.seq,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.revision,
    required this.payload,
    this.operationId,
    this.originDeviceId,
    this.changedAt,
  });

  final int seq;
  final String entityType;
  final String entityId;
  final String operationType;
  final int revision;
  final Map<String, dynamic> payload;
  final String? operationId;
  final String? originDeviceId;
  final DateTime? changedAt;
}

class PullPage {
  const PullPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PullChange> changes;
  final String nextCursor;
  final bool hasMore;
}

class SyncFailure implements Exception {
  const SyncFailure({
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

abstract interface class SyncApi {
  Future<List<PushOutcome>> push({
    required String accessToken,
    required List<SyncOperationRequest> operations,
  });

  Future<PullPage> pull({
    required String accessToken,
    required String cursor,
    int limit = 200,
  });
}

class DioSyncApi implements SyncApi {
  DioSyncApi({String baseUrl = apiBaseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$baseUrl/api/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              contentType: Headers.jsonContentType,
            ),
          );

  final Dio _dio;

  @override
  Future<List<PushOutcome>> push({
    required String accessToken,
    required List<SyncOperationRequest> operations,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/sync/push',
        data: {
          'operations': operations
              .map((operation) => operation.toJson())
              .toList(),
        },
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final results = response.data?['results'] as List<dynamic>? ?? const [];
      return results
          .map((item) => _outcome(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PullPage> pull({
    required String accessToken,
    required String cursor,
    int limit = 200,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/sync/pull',
        queryParameters: {'cursor': cursor, 'limit': limit},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data ?? const {};
      final changes = (data['changes'] as List<dynamic>? ?? const [])
          .map((item) => _change(item as Map<String, dynamic>))
          .toList();
      return PullPage(
        changes: changes,
        nextCursor: data['nextCursor'] as String? ?? cursor,
        hasMore: data['hasMore'] as bool? ?? false,
      );
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  static PushOutcome _outcome(Map<String, dynamic> json) => PushOutcome(
    operationId: json['operationId'] as String,
    status: json['status'] as String,
    entityId: json['entityId'] as String?,
    revision: (json['revision'] as num?)?.toInt(),
    changeSeq: (json['changeSeq'] as num?)?.toInt(),
    serverEntity: json['serverEntity'] as Map<String, dynamic>?,
    code: json['code'] as String?,
    message: json['message'] as String?,
  );

  static PullChange _change(Map<String, dynamic> json) => PullChange(
    seq: (json['seq'] as num).toInt(),
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    operationType: json['operationType'] as String,
    revision: (json['revision'] as num).toInt(),
    payload: json['payload'] as Map<String, dynamic>? ?? const {},
    operationId: json['operationId'] as String?,
    originDeviceId: json['originDeviceId'] as String?,
    changedAt: json['changedAt'] == null
        ? null
        : DateTime.tryParse(json['changedAt'] as String)?.toUtc(),
  );

  static SyncFailure _failure(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return SyncFailure(
        code: 'UNAUTHORIZED',
        message: 'Сессия истекла',
        unauthorized: true,
      );
    }
    if (error.response == null) {
      return const SyncFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер недоступен',
        network: true,
      );
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final body = data['error'];
      if (body is Map<String, dynamic>) {
        return SyncFailure(
          code: body['code'] as String? ?? 'SYNC_ERROR',
          message: body['message'] as String? ?? 'Ошибка синхронизации',
        );
      }
    }
    return SyncFailure(
      code: 'HTTP_$status',
      message: 'Ошибка синхронизации ($status)',
    );
  }
}
