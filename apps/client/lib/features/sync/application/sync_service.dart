import 'dart:convert';

import '../../../core/auth/session.dart';
import '../../../core/database/app_database.dart';
import '../../notes/data/notes_repository.dart';
import '../data/sync_api.dart';
import '../data/sync_repository.dart';

typedef SessionResolver = Future<Session?> Function({bool force});

class SyncSummary {
  const SyncSummary({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.offline = false,
    this.unauthorized = false,
    this.error,
  });

  final int pushed;
  final int pulled;
  final int conflicts;
  final int rejected;
  final bool offline;
  final bool unauthorized;
  final String? error;

  SyncSummary merge(SyncSummary other) => SyncSummary(
    pushed: pushed + other.pushed,
    pulled: pulled + other.pulled,
    conflicts: conflicts + other.conflicts,
    rejected: rejected + other.rejected,
    offline: offline || other.offline,
    unauthorized: unauthorized || other.unauthorized,
    error: other.error ?? error,
  );
}

class SyncService {
  SyncService({
    required this.database,
    required this.notes,
    required this.syncRepository,
    required this.api,
    required this.sessionResolver,
  });

  final AppDatabase database;
  final NotesRepository notes;
  final SyncRepository syncRepository;
  final SyncApi api;
  final SessionResolver sessionResolver;

  Future<SyncSummary> sync() async {
    var session = await sessionResolver(force: false);
    if (session == null) {
      return const SyncSummary(unauthorized: true);
    }

    try {
      return await _run(session);
    } on SyncFailure catch (failure) {
      if (!failure.unauthorized) {
        return SyncSummary(
          offline: failure.network,
          error: failure.network ? null : failure.message,
        );
      }

      session = await sessionResolver(force: true);
      if (session == null) {
        return const SyncSummary(unauthorized: true);
      }
      try {
        return await _run(session);
      } on SyncFailure catch (retryFailure) {
        return SyncSummary(
          offline: retryFailure.network,
          error: retryFailure.network ? null : retryFailure.message,
        );
      }
    }
  }

  Future<SyncSummary> _run(Session session) async {
    final pushed = await _push(session);
    final pulled = await _pull(session);
    return pushed.merge(pulled);
  }

  Future<SyncSummary> _push(Session session) async {
    var pushed = 0;
    var conflicts = 0;
    var rejected = 0;

    for (var batch = 0; batch < _maxPushBatches; batch += 1) {
      final pending = await notes.pendingOperations();
      if (pending.isEmpty) {
        break;
      }

      final operations = pending
          .map(
            (operation) => SyncOperationRequest(
              operationId: operation.operationId,
              deviceId: session.deviceId,
              entityType: operation.entityType,
              entityId: operation.entityId,
              operationType: operation.operationType,
              baseRevision: operation.baseRevision,
              clientTimestamp: operation.createdAt,
              payload: _decode(operation.payload),
            ),
          )
          .toList();

      final outcomes = await api.push(
        accessToken: session.accessToken,
        operations: operations,
      );
      final byId = {
        for (final outcome in outcomes) outcome.operationId: outcome,
      };
      var progress = false;

      for (final operation in pending) {
        final outcome = byId[operation.operationId];
        if (outcome == null) {
          await notes.markRejected(
            operationId: operation.operationId,
            noteId: operation.entityId,
            message: 'Сервер не вернул результат операции',
          );
          rejected += 1;
          continue;
        }

        switch (outcome.status) {
          case 'APPLIED':
          case 'DUPLICATE':
            await notes.applyPushSuccess(
              operationId: operation.operationId,
              noteId: operation.entityId,
              revision: outcome.revision ?? 1,
              sentPayload: operation.payload,
            );
            pushed += 1;
            progress = true;
          case 'CONFLICT':
            await syncRepository.saveConflict(
              userId: session.userId,
              entityId: operation.entityId,
              serverVersion: outcome.revision ?? 0,
              serverPayload: outcome.serverEntity ?? const {},
            );
            await notes.markConflict(
              noteId: operation.entityId,
              operationId: operation.operationId,
            );
            conflicts += 1;
            progress = true;
          case 'REJECTED':
            await notes.markRejected(
              operationId: operation.operationId,
              noteId: operation.entityId,
              message: outcome.message ?? outcome.code ?? 'Операция отклонена',
            );
            rejected += 1;
        }
      }

      if (!progress) {
        break;
      }
    }

    return SyncSummary(
      pushed: pushed,
      conflicts: conflicts,
      rejected: rejected,
    );
  }

  Future<SyncSummary> _pull(Session session) async {
    var cursor = await syncRepository.readCursor(session.userId);
    var pulled = 0;
    var conflicts = 0;

    for (var pageNumber = 0; pageNumber < _maxPullPages; pageNumber += 1) {
      final page = await api.pull(
        accessToken: session.accessToken,
        cursor: cursor,
        limit: _pullLimit,
      );

      await database.transaction(() async {
        for (final change in page.changes) {
          if (change.entityType != 'NOTE') {
            continue;
          }

          final pending = await notes.hasPendingOperation(change.entityId);
          final local = await notes.findById(change.entityId);
          if (pending || local?.syncStatus == 'CONFLICT') {
            await syncRepository.saveConflict(
              userId: session.userId,
              entityId: change.entityId,
              serverVersion: change.revision,
              serverPayload: change.payload,
            );
            await notes.setSyncStatus(change.entityId, 'CONFLICT');
            conflicts += 1;
            continue;
          }

          await notes.applyRemote(change.payload);
          pulled += 1;
        }

        await syncRepository.writeCursor(session.userId, page.nextCursor);
      });

      cursor = page.nextCursor;
      if (!page.hasMore) {
        break;
      }
    }

    return SyncSummary(pulled: pulled, conflicts: conflicts);
  }

  Map<String, dynamic>? _decode(String payload) {
    try {
      final value = payload.isEmpty ? null : payload;
      if (value == null) {
        return null;
      }
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static const int _pullLimit = 200;
  static const int _maxPushBatches = 10;
  static const int _maxPullPages = 50;
}
