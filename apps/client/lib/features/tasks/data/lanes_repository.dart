import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/lane.dart';

/// Дорожки доски. Настройка сохраняется локально и ставится в outbox.
class LanesRepository {
  LanesRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Lane>> watchAll() {
    final query = _database.select(_database.lanes)
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]);
    return query.watch().map((rows) => rows.map(_domain).toList());
  }

  Future<Lane?> findById(String id) async {
    final row = await (_database.select(
      _database.lanes,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _domain(row);
  }

  Future<String?> syncStatusFor(String id) async {
    final row = await (_database.select(
      _database.lanes,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row?.syncStatus;
  }

  Future<void> saveConfiguration(List<LaneDraft> drafts) async {
    final normalized = drafts
        .map((draft) => LaneDraft(id: draft.id, name: draft.name.trim()))
        .toList();
    if (normalized.length < minLanes || normalized.length > maxLanes) {
      throw ArgumentError('Нужно от $minLanes до $maxLanes дорожек');
    }
    if (normalized.any((draft) => draft.name.isEmpty)) {
      throw ArgumentError('Название дорожки не может быть пустым');
    }
    if (normalized.any((draft) => draft.name.length > 60)) {
      throw ArgumentError('Название дорожки слишком длинное');
    }
    if (normalized.map((draft) => draft.name).toSet().length !=
        normalized.length) {
      throw ArgumentError('Названия дорожек должны быть уникальны');
    }

    final current = await _activeLanes();
    final currentById = {for (final lane in current) lane.id: lane};
    final desiredIds = normalized
        .map((draft) => draft.id)
        .whereType<String>()
        .toSet();
    final deleted = current
        .where((lane) => !desiredIds.contains(lane.id))
        .toList();

    for (final draft in normalized) {
      if (draft.id != null && !currentById.containsKey(draft.id)) {
        throw ArgumentError('Дорожка не найдена');
      }
    }
    if (current.length -
            deleted.length +
            normalized.where((d) => d.id == null).length >
        maxLanes) {
      throw ArgumentError('Допустимо не более $maxLanes дорожек');
    }

    for (final lane in deleted) {
      final taskCount = await _taskCount(lane.id);
      if (taskCount > 0) {
        throw ArgumentError(
          'Сначала перенесите задачи из дорожки «${lane.name}»',
        );
      }
    }

    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      for (var index = 0; index < normalized.length; index += 1) {
        final draft = normalized[index];
        if (draft.id == null) {
          final id = _uuid.v4();
          await _database
              .into(_database.lanes)
              .insert(
                LanesCompanion.insert(
                  id: id,
                  name: draft.name,
                  sortOrder: index,
                  syncStatus: const Value('PENDING'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          await _database
              .into(_database.syncOutbox)
              .insert(
                SyncOutboxCompanion.insert(
                  operationId: _uuid.v4(),
                  entityType: 'LANE',
                  entityId: id,
                  operationType: 'CREATE',
                  payload: _payload(name: draft.name, sortOrder: index),
                  createdAt: now,
                ),
              );
          continue;
        }

        final lane = currentById[draft.id]!;
        if (lane.name == draft.name && lane.sortOrder == index) {
          continue;
        }
        await (_database.update(
          _database.lanes,
        )..where((table) => table.id.equals(lane.id))).write(
          LanesCompanion(
            name: Value(draft.name),
            sortOrder: Value(index),
            updatedAt: Value(now),
            syncStatus: const Value('PENDING'),
          ),
        );
        await _queueUpdate(
          lane: lane,
          name: draft.name,
          sortOrder: index,
          now: now,
        );
      }

      for (final lane in deleted) {
        await _deleteLane(lane, now);
      }
    });
  }

  Future<void> _queueUpdate({
    required Lane lane,
    required String name,
    required int sortOrder,
    required DateTime now,
  }) async {
    final pending = await _pendingFor(lane.id);
    final payload = _payload(name: name, sortOrder: sortOrder);
    if (pending == null) {
      await _database
          .into(_database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: _uuid.v4(),
              entityType: 'LANE',
              entityId: lane.id,
              operationType: 'UPDATE',
              payload: payload,
              baseRevision: Value(lane.revision),
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

  Future<void> _deleteLane(Lane lane, DateTime now) async {
    final pending = await _pendingFor(lane.id);
    if (pending?.operationType == 'CREATE') {
      await (_database.delete(
        _database.lanes,
      )..where((table) => table.id.equals(lane.id))).go();
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.entityId.equals(lane.id))).go();
      return;
    }
    await (_database.delete(_database.syncOutbox)..where(
          (table) =>
              table.entityId.equals(lane.id) &
              table.operationType.equals('UPDATE'),
        ))
        .go();
    await (_database.update(
      _database.lanes,
    )..where((table) => table.id.equals(lane.id))).write(
      LanesCompanion(
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
            entityType: 'LANE',
            entityId: lane.id,
            operationType: 'DELETE',
            payload: '{}',
            baseRevision: Value(lane.revision),
            createdAt: now,
          ),
        );
  }

  Future<void> applyPushSuccess({
    required String operationId,
    required String laneId,
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
        _database.lanes,
      )..where((table) => table.id.equals(laneId))).write(
        LanesCompanion(
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

  Future<void> setSyncStatus(String laneId, String status) async {
    await (_database.update(_database.lanes)
          ..where((table) => table.id.equals(laneId)))
        .write(LanesCompanion(syncStatus: Value(status)));
  }

  Future<void> markRejected({
    required String operationId,
    required String laneId,
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
      await (_database.update(_database.lanes)
            ..where((table) => table.id.equals(laneId)))
          .write(const LanesCompanion(syncStatus: Value('ERROR')));
    });
  }

  Future<void> markConflict({
    required String laneId,
    required String operationId,
  }) async {
    await _database.transaction(() async {
      await (_database.update(_database.lanes)
            ..where((table) => table.id.equals(laneId)))
          .write(const LanesCompanion(syncStatus: Value('CONFLICT')));
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.operationId.equals(operationId))).go();
    });
  }

  Future<void> applyRemote(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final existing = await (_database.select(
      _database.lanes,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final companion = LanesCompanion(
      id: Value(id),
      name: Value(payload['name'] as String? ?? 'Дорожка'),
      sortOrder: Value((payload['sortOrder'] as num?)?.toInt() ?? 0),
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
      await _database.into(_database.lanes).insert(companion);
    } else {
      await (_database.update(
        _database.lanes,
      )..where((table) => table.id.equals(id))).write(companion);
    }
  }

  Future<List<Lane>> _activeLanes() async {
    final rows =
        await (_database.select(_database.lanes)
              ..where((table) => table.deletedAt.isNull())
              ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
            .get();
    return rows.map(_domain).toList();
  }

  Future<int> _taskCount(String laneId) async {
    final count = _database.tasks.id.count();
    final row =
        await (_database.selectOnly(_database.tasks)
              ..addColumns([count])
              ..where(
                _database.tasks.laneId.equals(laneId) &
                    _database.tasks.deletedAt.isNull(),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<SyncOutboxData?> _pendingFor(String laneId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(laneId))
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  static Lane _domain(LaneRow row) => Lane(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    revision: row.revision,
    syncStatus: row.syncStatus,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static String _payload({required String name, required int sortOrder}) =>
      jsonEncode({'name': name, 'sortOrder': sortOrder});

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static const minLanes = 3;
  static const maxLanes = 10;
}
