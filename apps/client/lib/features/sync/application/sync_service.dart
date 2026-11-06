import 'dart:convert';

import '../../../core/auth/session.dart';
import '../../../core/database/app_database.dart';
import '../../attachments/data/attachments_repository.dart';
import '../../calendar/data/reminders_repository.dart';
import '../../notes/data/notes_repository.dart';
import '../../tasks/data/lanes_repository.dart';
import '../../tasks/data/tasks_repository.dart';
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
    required this.tasks,
    required this.lanes,
    required this.reminders,
    required this.attachments,
    required this.syncRepository,
    required this.api,
    required this.sessionResolver,
  });

  final AppDatabase database;
  final NotesRepository notes;
  final TasksRepository tasks;
  final LanesRepository lanes;
  final RemindersRepository reminders;
  final AttachmentsRepository attachments;
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
      final pending = _orderedForPush(await syncRepository.pendingOperations());
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
          await _markRejected(
            operation: operation,
            message: 'Сервер не вернул результат операции',
          );
          rejected += 1;
          continue;
        }

        switch (outcome.status) {
          case 'APPLIED':
          case 'DUPLICATE':
            await _applyPushSuccess(operation, outcome.revision ?? 1);
            pushed += 1;
            progress = true;
          case 'CONFLICT':
            await syncRepository.saveConflict(
              userId: session.userId,
              entityType: operation.entityType,
              entityId: operation.entityId,
              serverVersion: outcome.revision ?? 0,
              serverPayload: outcome.serverEntity ?? const {},
            );
            await _markConflict(operation);
            conflicts += 1;
            progress = true;
          case 'REJECTED':
            await _markRejected(
              operation: operation,
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

  Future<void> _applyPushSuccess(SyncOutboxData operation, int revision) async {
    switch (operation.entityType) {
      case 'NOTE':
        await notes.applyPushSuccess(
          operationId: operation.operationId,
          noteId: operation.entityId,
          revision: revision,
          sentPayload: operation.payload,
        );
      case 'TASK':
        await tasks.applyPushSuccess(
          operationId: operation.operationId,
          taskId: operation.entityId,
          revision: revision,
          sentPayload: operation.payload,
        );
      case 'LANE':
        await lanes.applyPushSuccess(
          operationId: operation.operationId,
          laneId: operation.entityId,
          revision: revision,
          sentPayload: operation.payload,
        );
      case 'REMINDER':
        await reminders.applyPushSuccess(
          operationId: operation.operationId,
          reminderId: operation.entityId,
          revision: revision,
          sentPayload: operation.payload,
        );
    }
  }

  Future<void> _markConflict(SyncOutboxData operation) async {
    switch (operation.entityType) {
      case 'NOTE':
        await notes.markConflict(
          noteId: operation.entityId,
          operationId: operation.operationId,
        );
      case 'TASK':
        await tasks.markConflict(
          taskId: operation.entityId,
          operationId: operation.operationId,
        );
      case 'LANE':
        await lanes.markConflict(
          laneId: operation.entityId,
          operationId: operation.operationId,
        );
      case 'REMINDER':
        await reminders.markConflict(
          reminderId: operation.entityId,
          operationId: operation.operationId,
        );
    }
  }

  Future<void> _markRejected({
    required SyncOutboxData operation,
    required String message,
  }) async {
    switch (operation.entityType) {
      case 'NOTE':
        await notes.markRejected(
          operationId: operation.operationId,
          noteId: operation.entityId,
          message: message,
        );
      case 'TASK':
        await tasks.markRejected(
          operationId: operation.operationId,
          taskId: operation.entityId,
          message: message,
        );
      case 'LANE':
        await lanes.markRejected(
          operationId: operation.operationId,
          laneId: operation.entityId,
          message: message,
        );
      case 'REMINDER':
        await reminders.markRejected(
          operationId: operation.operationId,
          reminderId: operation.entityId,
          message: message,
        );
    }
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
          if (!_supportedEntities.contains(change.entityType)) {
            continue;
          }

          final pending = await syncRepository.hasPendingOperation(
            change.entityId,
          );
          final status = await _localStatus(change.entityType, change.entityId);
          if (pending || status == 'CONFLICT') {
            await syncRepository.saveConflict(
              userId: session.userId,
              entityType: change.entityType,
              entityId: change.entityId,
              serverVersion: change.revision,
              serverPayload: change.payload,
            );
            await _setConflict(change.entityType, change.entityId);
            conflicts += 1;
            continue;
          }

          switch (change.entityType) {
            case 'NOTE':
              await notes.applyRemote(change.payload);
            case 'TASK':
              await tasks.applyRemote(
                change.payload,
                operationId: change.operationId,
              );
            case 'LANE':
              await lanes.applyRemote(change.payload);
            case 'REMINDER':
              await reminders.applyRemote(change.payload);
            case 'ATTACHMENT':
              await attachments.applyRemote(change.payload);
          }
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

  Future<String?> _localStatus(String entityType, String entityId) async {
    return switch (entityType) {
      'NOTE' => (await notes.findById(entityId))?.syncStatus,
      'TASK' => (await tasks.findById(entityId))?.syncStatus,
      'LANE' => (await lanes.findById(entityId))?.syncStatus,
      'REMINDER' => (await reminders.syncStatusFor(entityId)),
      _ => null,
    };
  }

  Future<void> _setConflict(String entityType, String entityId) async {
    switch (entityType) {
      case 'NOTE':
        await notes.setSyncStatus(entityId, 'CONFLICT');
      case 'TASK':
        await tasks.setSyncStatus(entityId, 'CONFLICT');
      case 'LANE':
        await lanes.setSyncStatus(entityId, 'CONFLICT');
      case 'REMINDER':
        await reminders.setSyncStatus(entityId, 'CONFLICT');
    }
  }

  List<SyncOutboxData> _orderedForPush(List<SyncOutboxData> pending) {
    final ordered = [...pending];
    ordered.sort((a, b) {
      final rank = _pushRank(a).compareTo(_pushRank(b));
      if (rank != 0) {
        return rank;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return ordered;
  }

  static int _pushRank(SyncOutboxData operation) {
    if (operation.entityType == 'LANE' && operation.operationType == 'DELETE') {
      return 40;
    }
    return switch (operation.entityType) {
      'LANE' => 0,
      'TASK' => 10,
      'REMINDER' => 20,
      'NOTE' => 30,
      _ => 35,
    };
  }

  Map<String, dynamic>? _decode(String payload) {
    if (payload.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static const int _pullLimit = 200;
  static const int _maxPushBatches = 10;
  static const int _maxPullPages = 50;
  static const _supportedEntities = {
    'NOTE',
    'TASK',
    'LANE',
    'REMINDER',
    'ATTACHMENT',
  };
}
