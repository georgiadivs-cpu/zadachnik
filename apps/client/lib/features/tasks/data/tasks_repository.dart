import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/task.dart';
import '../domain/task_history_entry.dart';

/// Задачи доски, их outbox-операции и локальная история перемещений.
class TasksRepository {
  TasksRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Task>> watchAll() {
    final query =
        _database.select(_database.tasks).join([
            leftOuterJoin(
              _database.categories,
              _database.categories.id.equalsExp(_database.tasks.categoryId),
            ),
          ])
          ..where(_database.tasks.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(_database.tasks.createdAt)]);
    return query.watch().map(
      (rows) => rows.map((row) {
        final task = row.readTable(_database.tasks);
        final category = row.readTableOrNull(_database.categories);
        return _domain(task, category?.name);
      }).toList(),
    );
  }

  Future<Task?> findById(String id) async {
    final row = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    final category =
        await (_database.select(_database.categories)
              ..where((table) => table.id.equals(row.categoryId ?? '')))
            .getSingleOrNull();
    return _domain(row, category?.name);
  }

  Future<String?> syncStatusFor(String id) async {
    final row = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row?.syncStatus;
  }

  Future<String> create(TaskDraft draft) async {
    final normalized = _validate(draft);
    await _requireLane(normalized.laneId);

    final id = _uuid.v4();
    final operationId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final payload = _payload(normalized);

    await _database.transaction(() async {
      await _database
          .into(_database.tasks)
          .insert(
            TasksCompanion.insert(
              id: id,
              title: normalized.title,
              description: Value(normalized.description),
              laneId: normalized.laneId,
              categoryId: Value(normalized.categoryId),
              priority: Value(normalized.priority),
              plannedStartAt: Value(normalized.plannedStartAt),
              plannedEndAt: Value(normalized.plannedEndAt),
              actualStartAt: Value(normalized.actualStartAt),
              actualEndAt: Value(normalized.actualEndAt),
              createdAt: now,
              updatedAt: now,
              syncStatus: const Value('PENDING'),
            ),
          );
      await _database
          .into(_database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: operationId,
              entityType: 'TASK',
              entityId: id,
              operationType: 'CREATE',
              payload: payload,
              createdAt: now,
            ),
          );
      await _insertHistory(
        taskId: id,
        fromLaneId: null,
        toLaneId: normalized.laneId,
        operationId: operationId,
        changedAt: now,
        source: 'local',
      );
    });
    return id;
  }

  Future<void> updateLocal(Task task, TaskDraft draft) async {
    final normalized = _validate(draft);
    await _requireLane(normalized.laneId);

    final now = DateTime.now().toUtc();
    final payload = _payload(normalized, systemState: task.systemState);
    final laneChanged = task.laneId != normalized.laneId;

    await _database.transaction(() async {
      await (_database.update(
        _database.tasks,
      )..where((table) => table.id.equals(task.id))).write(
        TasksCompanion(
          title: Value(normalized.title),
          description: Value(normalized.description),
          laneId: Value(normalized.laneId),
          categoryId: Value(normalized.categoryId),
          priority: Value(normalized.priority),
          plannedStartAt: Value(normalized.plannedStartAt),
          plannedEndAt: Value(normalized.plannedEndAt),
          actualStartAt: Value(normalized.actualStartAt),
          actualEndAt: Value(normalized.actualEndAt),
          updatedAt: Value(now),
          syncStatus: const Value('PENDING'),
        ),
      );

      final operationId = await _queueUpdate(
        task: task,
        payload: payload,
        now: now,
      );
      if (laneChanged) {
        await _insertHistory(
          taskId: task.id,
          fromLaneId: task.laneId,
          toLaneId: normalized.laneId,
          operationId: operationId,
          changedAt: now,
          source: 'local',
        );
      }
    });
  }

  Future<void> setCancelled(Task task, bool cancelled) async {
    final now = DateTime.now().toUtc();
    final state = cancelled ? 'CANCELLED' : 'ACTIVE';
    final payload = _payloadFromTask(task, systemState: state);

    await _database.transaction(() async {
      await (_database.update(
        _database.tasks,
      )..where((table) => table.id.equals(task.id))).write(
        TasksCompanion(
          systemState: Value(state),
          updatedAt: Value(now),
          syncStatus: const Value('PENDING'),
        ),
      );
      await _queueUpdate(task: task, payload: payload, now: now);
    });
  }

  Future<void> moveToLane(Task task, String laneId) async {
    if (task.laneId == laneId) {
      return;
    }
    await updateLocal(task, TaskDraft.fromTask(task).copyWith(laneId: laneId));
  }

  Future<String> _queueUpdate({
    required Task task,
    required String payload,
    required DateTime now,
  }) async {
    final pending = await _pendingFor(task.id);
    if (pending == null) {
      final operationId = _uuid.v4();
      await _database
          .into(_database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: operationId,
              entityType: 'TASK',
              entityId: task.id,
              operationType: 'UPDATE',
              payload: payload,
              baseRevision: Value(task.revision),
              createdAt: now,
            ),
          );
      return operationId;
    }
    if (pending.operationType == 'CREATE' ||
        pending.operationType == 'UPDATE') {
      await (_database.update(_database.syncOutbox)
            ..where((table) => table.operationId.equals(pending.operationId)))
          .write(SyncOutboxCompanion(payload: Value(payload)));
      return pending.operationId;
    }
    return pending.operationId;
  }

  Future<void> applyPushSuccess({
    required String operationId,
    required String taskId,
    required int revision,
    required String sentPayload,
  }) async {
    await _database.transaction(() async {
      final operation =
          await (_database.select(_database.syncOutbox)
                ..where((table) => table.operationId.equals(operationId)))
              .getSingleOrNull();
      final editedDuringPush =
          operation != null && operation.payload != sentPayload;
      await (_database.update(
        _database.tasks,
      )..where((table) => table.id.equals(taskId))).write(
        TasksCompanion(
          revision: Value(revision),
          syncStatus: Value(editedDuringPush ? 'PENDING' : 'SYNCED'),
        ),
      );
      if (operation == null) {
        return;
      }
      if (!editedDuringPush) {
        await (_database.delete(
          _database.syncOutbox,
        )..where((table) => table.operationId.equals(operationId))).go();
        return;
      }
      await (_database.update(
        _database.syncOutbox,
      )..where((table) => table.operationId.equals(operationId))).write(
        SyncOutboxCompanion(
          operationType: const Value('UPDATE'),
          baseRevision: Value(revision),
          attempts: const Value(0),
          lastError: const Value(null),
        ),
      );
    });
  }

  Future<void> setSyncStatus(String taskId, String status) async {
    await (_database.update(_database.tasks)
          ..where((table) => table.id.equals(taskId)))
        .write(TasksCompanion(syncStatus: Value(status)));
  }

  Future<void> markRejected({
    required String operationId,
    required String taskId,
    required String message,
  }) async {
    await _database.transaction(() async {
      final operation =
          await (_database.select(_database.syncOutbox)
                ..where((table) => table.operationId.equals(operationId)))
              .getSingleOrNull();
      if (operation != null) {
        await (_database.update(
          _database.syncOutbox,
        )..where((table) => table.operationId.equals(operationId))).write(
          SyncOutboxCompanion(
            attempts: Value(operation.attempts + 1),
            lastError: Value(message),
          ),
        );
      }
      await (_database.update(_database.tasks)
            ..where((table) => table.id.equals(taskId)))
          .write(const TasksCompanion(syncStatus: Value('ERROR')));
    });
  }

  Future<void> markConflict({
    required String taskId,
    required String operationId,
  }) async {
    await _database.transaction(() async {
      await (_database.update(_database.tasks)
            ..where((table) => table.id.equals(taskId)))
          .write(const TasksCompanion(syncStatus: Value('CONFLICT')));
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.operationId.equals(operationId))).go();
    });
  }

  Future<void> applyRemote(
    Map<String, dynamic> payload, {
    String? operationId,
  }) async {
    final id = payload['id'] as String;
    final laneId = payload['laneId'] as String? ?? '';
    if (!await _laneExists(laneId)) {
      throw StateError('Локальная дорожка $laneId не найдена');
    }

    final existing = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final categoryId = payload['categoryId'] as String?;
    final validCategory =
        categoryId != null && await _categoryExists(categoryId)
        ? categoryId
        : null;
    final companion = TasksCompanion(
      id: Value(id),
      title: Value(payload['title'] as String? ?? 'Задача'),
      description: Value(payload['description'] as String? ?? ''),
      laneId: Value(laneId),
      systemState: Value(
        (payload['systemState'] as String? ?? 'ACTIVE').toUpperCase(),
      ),
      categoryId: Value(validCategory),
      priority: Value(
        (payload['priority'] as String? ?? 'NORMAL').toUpperCase(),
      ),
      plannedStartAt: Value(_date(payload['plannedStartAt'])),
      plannedEndAt: Value(_date(payload['plannedEndAt'])),
      actualStartAt: Value(_date(payload['actualStartAt'])),
      actualEndAt: Value(_date(payload['actualEndAt'])),
      revision: Value((payload['revision'] as num?)?.toInt() ?? 1),
      syncStatus: const Value('SYNCED'),
      createdAt: Value(
        _date(payload['createdAt']) ?? existing?.createdAt ?? now,
      ),
      updatedAt: Value(
        _date(payload['updatedAt']) ?? existing?.updatedAt ?? now,
      ),
      deletedAt: Value(_date(payload['deletedAt'])),
    );

    if (existing == null) {
      await _database.into(_database.tasks).insert(companion);
    } else {
      await (_database.update(
        _database.tasks,
      )..where((table) => table.id.equals(id))).write(companion);
    }

    if ((existing == null || existing.laneId != laneId) &&
        operationId != null &&
        !await historyExists(operationId)) {
      await _insertHistory(
        taskId: id,
        fromLaneId: existing?.laneId,
        toLaneId: laneId,
        operationId: operationId,
        changedAt: _date(payload['updatedAt']) ?? now,
        source: 'remote',
      );
    }
  }

  Stream<List<TaskHistoryEntry>> watchHistory(String taskId) {
    final query = _database.select(_database.taskStatusHistory)
      ..where((table) => table.taskId.equals(taskId))
      ..orderBy([(table) => OrderingTerm.desc(table.sequence)]);
    return query.watch().map((rows) => rows.map(_historyDomain).toList());
  }

  Future<bool> historyExists(String operationId) async {
    final row =
        await (_database.select(_database.taskStatusHistory)
              ..where((table) => table.operationId.equals(operationId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> _insertHistory({
    required String taskId,
    required String? fromLaneId,
    required String toLaneId,
    required String operationId,
    required DateTime changedAt,
    required String source,
  }) async {
    await _database
        .into(_database.taskStatusHistory)
        .insert(
          TaskStatusHistoryCompanion.insert(
            id: _uuid.v4(),
            taskId: taskId,
            fromLaneId: Value(fromLaneId),
            toLaneId: toLaneId,
            operationId: Value(operationId),
            changedAt: changedAt,
            source: source,
          ),
        );
  }

  Future<SyncOutboxData?> _pendingFor(String taskId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(taskId))
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> _requireLane(String laneId) async {
    if (!await _laneExists(laneId)) {
      throw ArgumentError('Дорожка не найдена');
    }
  }

  Future<bool> _laneExists(String laneId) async {
    final row = await (_database.select(
      _database.lanes,
    )..where((table) => table.id.equals(laneId))).getSingleOrNull();
    return row != null;
  }

  Future<bool> _categoryExists(String id) async {
    final row = await (_database.select(
      _database.categories,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row != null;
  }

  TaskDraft _validate(TaskDraft draft) {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw ArgumentError('Название задачи обязательно');
    }
    if (title.length > 200) {
      throw ArgumentError('Название задачи слишком длинное');
    }
    if (draft.description.length > 10000) {
      throw ArgumentError('Описание задачи слишком длинное');
    }
    if (draft.plannedStartAt != null &&
        draft.plannedEndAt != null &&
        draft.plannedEndAt!.isBefore(draft.plannedStartAt!)) {
      throw ArgumentError('Плановое завершение раньше начала');
    }
    if (draft.actualStartAt != null &&
        draft.actualEndAt != null &&
        draft.actualEndAt!.isBefore(draft.actualStartAt!)) {
      throw ArgumentError('Фактическое завершение раньше начала');
    }
    return TaskDraft(
      title: title,
      description: draft.description,
      laneId: draft.laneId,
      categoryId: draft.categoryId,
      priority: draft.priority,
      plannedStartAt: draft.plannedStartAt,
      plannedEndAt: draft.plannedEndAt,
      actualStartAt: draft.actualStartAt,
      actualEndAt: draft.actualEndAt,
    );
  }

  static Task _domain(TaskRow row, String? categoryName) => Task(
    id: row.id,
    title: row.title,
    description: row.description,
    laneId: row.laneId,
    systemState: row.systemState,
    categoryId: row.categoryId,
    categoryName: categoryName,
    priority: row.priority,
    plannedStartAt: row.plannedStartAt,
    plannedEndAt: row.plannedEndAt,
    actualStartAt: row.actualStartAt,
    actualEndAt: row.actualEndAt,
    revision: row.revision,
    syncStatus: row.syncStatus,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static TaskHistoryEntry _historyDomain(TaskHistoryRow row) =>
      TaskHistoryEntry(
        id: row.id,
        taskId: row.taskId,
        fromLaneId: row.fromLaneId,
        toLaneId: row.toLaneId,
        operationId: row.operationId,
        changedAt: row.changedAt,
        source: row.source,
      );

  static String _payload(TaskDraft draft, {String systemState = 'ACTIVE'}) =>
      jsonEncode({
        'title': draft.title,
        'description': draft.description,
        'laneId': draft.laneId,
        'systemState': systemState,
        'categoryId': draft.categoryId,
        'priority': draft.priority,
        'plannedStartAt': draft.plannedStartAt?.toUtc().toIso8601String(),
        'plannedEndAt': draft.plannedEndAt?.toUtc().toIso8601String(),
        'actualStartAt': draft.actualStartAt?.toUtc().toIso8601String(),
        'actualEndAt': draft.actualEndAt?.toUtc().toIso8601String(),
      });

  static String _payloadFromTask(Task task, {required String systemState}) =>
      jsonEncode({
        'title': task.title,
        'description': task.description,
        'laneId': task.laneId,
        'systemState': systemState,
        'categoryId': task.categoryId,
        'priority': task.priority,
        'plannedStartAt': task.plannedStartAt?.toUtc().toIso8601String(),
        'plannedEndAt': task.plannedEndAt?.toUtc().toIso8601String(),
        'actualStartAt': task.actualStartAt?.toUtc().toIso8601String(),
        'actualEndAt': task.actualEndAt?.toUtc().toIso8601String(),
      });

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
