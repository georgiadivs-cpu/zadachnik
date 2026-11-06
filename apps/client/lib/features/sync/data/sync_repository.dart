import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class SyncRepository {
  SyncRepository(this._database);

  final AppDatabase _database;

  Future<String> readCursor(String userId) async {
    final row = await (_database.select(
      _database.syncStates,
    )..where((table) => table.userId.equals(userId))).getSingleOrNull();
    return row?.cursor ?? '0';
  }

  Future<void> writeCursor(String userId, String cursor) async {
    await _database
        .into(_database.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            userId: userId,
            cursor: cursor,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> saveConflict({
    required String userId,
    required String entityType,
    required String entityId,
    required int serverVersion,
    required Map<String, dynamic> serverPayload,
  }) async {
    await (_database.delete(_database.conflicts)..where(
          (table) =>
              table.userId.equals(userId) & table.entityId.equals(entityId),
        ))
        .go();
    await _database
        .into(_database.conflicts)
        .insert(
          ConflictsCompanion.insert(
            id: '$userId:$entityId',
            userId: userId,
            entityType: entityType,
            entityId: entityId,
            serverPayload: jsonEncode(serverPayload),
            serverVersion: serverVersion,
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<List<SyncOutboxData>> pendingOperations({int limit = 100}) {
    final query = _database.select(_database.syncOutbox)
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<bool> hasPendingOperation(String entityId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(entityId))
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<int> pendingCount() async {
    final count = _database.syncOutbox.operationId.count();
    final row = await (_database.selectOnly(
      _database.syncOutbox,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> conflictCount(String userId) async {
    final count = _database.conflicts.id.count();
    final row =
        await (_database.selectOnly(_database.conflicts)
              ..addColumns([count])
              ..where(_database.conflicts.userId.equals(userId)))
            .getSingle();
    return row.read(count) ?? 0;
  }
}
