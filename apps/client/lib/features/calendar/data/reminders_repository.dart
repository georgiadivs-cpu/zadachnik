import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/task_reminder.dart';

/// Напоминания задач: одно активное на задачу, время в UTC.
class RemindersRepository {
  RemindersRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<TaskReminder>> watchAll() {
    final query = _database.select(_database.taskReminders)
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.asc(table.remindAt)]);
    return query.watch().map((rows) => rows.map(_domain).toList());
  }

  Future<List<TaskReminder>> listAllActive() async {
    final rows =
        await (_database.select(_database.taskReminders)
              ..where((table) => table.deletedAt.isNull())
              ..orderBy([(table) => OrderingTerm.asc(table.remindAt)]))
            .get();
    return rows.map(_domain).toList();
  }

  Future<TaskReminder?> findForTask(String taskId) async {
    final row =
        await (_database.select(_database.taskReminders)
              ..where(
                (table) =>
                    table.taskId.equals(taskId) & table.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _domain(row);
  }

  Future<String?> syncStatusFor(String id) async {
    final row = await (_database.select(
      _database.taskReminders,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row?.syncStatus;
  }

  /// Создаёт, обновляет или удаляет единственное напоминание задачи.
  Future<TaskReminder?> saveForTask(
    String taskId,
    DateTime? remindAtUtc,
  ) async {
    final existing = await findForTask(taskId);
    final now = DateTime.now().toUtc();

    if (remindAtUtc == null) {
      if (existing != null) {
        await _delete(existing, now);
      }
      return null;
    }

    final remindAt = remindAtUtc.toUtc();
    if (existing != null) {
      if (existing.remindAt == remindAt) {
        return existing;
      }
      final payload = _payload(taskId: taskId, remindAt: remindAt);
      await _database.transaction(() async {
        await (_database.update(
          _database.taskReminders,
        )..where((table) => table.id.equals(existing.id))).write(
          TaskRemindersCompanion(
            remindAt: Value(remindAt),
            updatedAt: Value(now),
            syncStatus: const Value('PENDING'),
          ),
        );
        await _queueUpdate(existing, payload, now);
      });
      return findForTask(taskId);
    }

    final id = _uuid.v4();
    final operationId = _uuid.v4();
    final payload = _payload(taskId: taskId, remindAt: remindAt);
    await _database.transaction(() async {
      await _database
          .into(_database.taskReminders)
          .insert(
            TaskRemindersCompanion.insert(
              id: id,
              taskId: taskId,
              remindAt: remindAt,
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
              entityType: 'REMINDER',
              entityId: id,
              operationType: 'CREATE',
              payload: payload,
              createdAt: now,
            ),
          );
    });
    return findForTask(taskId);
  }

  Future<void> _delete(TaskReminder reminder, DateTime now) async {
    final pending = await _pendingFor(reminder.id);
    if (pending?.operationType == 'CREATE') {
      await (_database.delete(
        _database.taskReminders,
      )..where((table) => table.id.equals(reminder.id))).go();
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.entityId.equals(reminder.id))).go();
      return;
    }

    await (_database.delete(_database.syncOutbox)..where(
          (table) =>
              table.entityId.equals(reminder.id) &
              table.operationType.equals('UPDATE'),
        ))
        .go();
    await (_database.update(
      _database.taskReminders,
    )..where((table) => table.id.equals(reminder.id))).write(
      TaskRemindersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('PENDING'),
      ),
    );
    await _database
        .into(_database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            operationId: _uuid.v4(),
            entityType: 'REMINDER',
            entityId: reminder.id,
            operationType: 'DELETE',
            payload: '{}',
            baseRevision: Value(reminder.revision),
            createdAt: now,
          ),
        );
  }

  Future<void> _queueUpdate(
    TaskReminder reminder,
    String payload,
    DateTime now,
  ) async {
    final pending = await _pendingFor(reminder.id);
    if (pending == null) {
      await _database
          .into(_database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: _uuid.v4(),
              entityType: 'REMINDER',
              entityId: reminder.id,
              operationType: 'UPDATE',
              payload: payload,
              baseRevision: Value(reminder.revision),
              createdAt: now,
            ),
          );
      return;
    }
    if (pending.operationType == 'CREATE' ||
        pending.operationType == 'UPDATE') {
      await (_database.update(_database.syncOutbox)
            ..where((table) => table.operationId.equals(pending.operationId)))
          .write(SyncOutboxCompanion(payload: Value(payload)));
    }
  }

  Future<void> applyPushSuccess({
    required String operationId,
    required String reminderId,
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
        _database.taskReminders,
      )..where((table) => table.id.equals(reminderId))).write(
        TaskRemindersCompanion(
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

  Future<void> markRejected({
    required String operationId,
    required String reminderId,
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
      await (_database.update(_database.taskReminders)
            ..where((table) => table.id.equals(reminderId)))
          .write(const TaskRemindersCompanion(syncStatus: Value('ERROR')));
    });
  }

  Future<void> markConflict({
    required String reminderId,
    required String operationId,
  }) async {
    await _database.transaction(() async {
      await (_database.update(_database.taskReminders)
            ..where((table) => table.id.equals(reminderId)))
          .write(const TaskRemindersCompanion(syncStatus: Value('CONFLICT')));
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.operationId.equals(operationId))).go();
    });
  }

  Future<void> setSyncStatus(String reminderId, String status) async {
    await (_database.update(_database.taskReminders)
          ..where((table) => table.id.equals(reminderId)))
        .write(TaskRemindersCompanion(syncStatus: Value(status)));
  }

  Future<void> applyRemote(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final taskId = payload['taskId'] as String;
    final taskExists = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).getSingleOrNull();
    if (taskExists == null) {
      throw StateError('Задача $taskId для напоминания не найдена');
    }
    final remindAt = _date(payload['remindAt']);
    if (remindAt == null) {
      throw StateError('remindAt обязателен');
    }

    final existing = await (_database.select(
      _database.taskReminders,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final companion = TaskRemindersCompanion(
      id: Value(id),
      taskId: Value(taskId),
      remindAt: Value(remindAt),
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
      await _database.into(_database.taskReminders).insert(companion);
    } else {
      await (_database.update(
        _database.taskReminders,
      )..where((table) => table.id.equals(id))).write(companion);
    }
  }

  Future<SyncOutboxData?> _pendingFor(String reminderId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(reminderId))
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  static TaskReminder _domain(ReminderRow row) => TaskReminder(
    id: row.id,
    taskId: row.taskId,
    remindAt: row.remindAt.toUtc(),
    revision: row.revision,
    syncStatus: row.syncStatus,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
  );

  static String _payload({
    required String taskId,
    required DateTime remindAt,
  }) => jsonEncode({
    'taskId': taskId,
    'remindAt': remindAt.toUtc().toIso8601String(),
  });

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
