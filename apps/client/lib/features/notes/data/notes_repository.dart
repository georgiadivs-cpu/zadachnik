import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/note.dart';

/// Локальные операции с заметками, outbox и применением серверных изменений.
class NotesRepository {
  NotesRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<Note>> watchAll() {
    final query =
        _database.select(_database.notes).join([
            leftOuterJoin(
              _database.categories,
              _database.categories.id.equalsExp(_database.notes.categoryId),
            ),
          ])
          ..where(_database.notes.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(_database.notes.updatedAt)]);

    return query.watch().map(
      (rows) => rows.map((row) {
        final note = row.readTable(_database.notes);
        final category = row.readTableOrNull(_database.categories);
        return _domain(note, category?.name);
      }).toList(),
    );
  }

  Future<List<Note>> listAll() async {
    final rows =
        await (_database.select(_database.notes)
              ..where((table) => table.deletedAt.isNull())
              ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]))
            .get();
    final result = <Note>[];
    for (final row in rows) {
      final category =
          await (_database.select(_database.categories)
                ..where((table) => table.id.equals(row.categoryId ?? '')))
              .getSingleOrNull();
      result.add(_domain(row, category?.name));
    }
    return result;
  }

  Future<Note?> findById(String id) async {
    final query = _database.select(_database.notes)
      ..where((table) => table.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }

    final category =
        await (_database.select(_database.categories)
              ..where((table) => table.id.equals(row.categoryId ?? '')))
            .getSingleOrNull();
    return _domain(row, category?.name);
  }

  Future<String> create({
    required String title,
    required String contentMarkdown,
    required String categoryId,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError('Заголовок заметки обязателен');
    }

    final id = _uuid.v4();
    final operationId = _uuid.v4();
    final now = DateTime.now().toUtc();

    await _database.transaction(() async {
      await _database
          .into(_database.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              title: normalizedTitle,
              contentMarkdown: Value(contentMarkdown),
              categoryId: Value(categoryId),
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
              entityType: 'NOTE',
              entityId: id,
              operationType: 'CREATE',
              payload: _payload(
                title: normalizedTitle,
                contentMarkdown: contentMarkdown,
                categoryId: categoryId,
              ),
              createdAt: now,
            ),
          );
    });

    return id;
  }

  /// Обновляет локальную заметку и ставит/обновляет одну операцию UPDATE.
  Future<void> updateLocal({
    required Note note,
    required String title,
    required String contentMarkdown,
    required String categoryId,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError('Заголовок заметки обязателен');
    }

    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.update(
        _database.notes,
      )..where((table) => table.id.equals(note.id))).write(
        NotesCompanion(
          title: Value(normalizedTitle),
          contentMarkdown: Value(contentMarkdown),
          categoryId: Value(categoryId),
          updatedAt: Value(now),
          syncStatus: const Value('PENDING'),
        ),
      );

      final pending = await _pendingFor(note.id);
      final payload = _payload(
        title: normalizedTitle,
        contentMarkdown: contentMarkdown,
        categoryId: categoryId,
      );

      if (pending == null) {
        await _database
            .into(_database.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                operationId: _uuid.v4(),
                entityType: 'NOTE',
                entityId: note.id,
                operationType: 'UPDATE',
                payload: payload,
                baseRevision: Value(note.revision),
                createdAt: now,
              ),
            );
      } else if (pending.operationType == 'CREATE' ||
          pending.operationType == 'UPDATE') {
        await (_database.update(_database.syncOutbox)
              ..where((table) => table.operationId.equals(pending.operationId)))
            .write(SyncOutboxCompanion(payload: Value(payload)));
      }
    });
  }

  /// Мягкое удаление. Неотправленное создание отменяется локально.
  Future<void> deleteLocal(Note note) async {
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      final pending = await _pendingFor(note.id);
      if (pending?.operationType == 'CREATE') {
        await (_database.delete(
          _database.notes,
        )..where((table) => table.id.equals(note.id))).go();
        await (_database.delete(
          _database.syncOutbox,
        )..where((table) => table.entityId.equals(note.id))).go();
        return;
      }

      await (_database.delete(_database.syncOutbox)..where(
            (table) =>
                table.entityId.equals(note.id) &
                table.operationType.equals('UPDATE'),
          ))
          .go();

      await (_database.update(
        _database.notes,
      )..where((table) => table.id.equals(note.id))).write(
        NotesCompanion(
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
              entityType: 'NOTE',
              entityId: note.id,
              operationType: 'DELETE',
              payload: '{}',
              baseRevision: Value(note.revision),
              createdAt: now,
            ),
          );
    });
  }

  Future<List<SyncOutboxData>> pendingOperations({int limit = 100}) {
    final query = _database.select(_database.syncOutbox)
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<bool> hasPendingOperation(String noteId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(noteId))
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<void> applyPushSuccess({
    required String operationId,
    required String noteId,
    required int revision,
    required String sentPayload,
  }) async {
    await _database.transaction(() async {
      final operation =
          await (_database.select(_database.syncOutbox)
                ..where((table) => table.operationId.equals(operationId)))
              .getSingleOrNull();

      // Пока запрос был в пути, пользователь мог изменить заметку.
      // В этом случае операция не удаляется, а переотправляется поверх
      // полученной серверной revision.
      final editedDuringPush =
          operation != null && operation.payload != sentPayload;

      await (_database.update(
        _database.notes,
      )..where((table) => table.id.equals(noteId))).write(
        NotesCompanion(
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
    required String noteId,
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
      await (_database.update(_database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(const NotesCompanion(syncStatus: Value('ERROR')));
    });
  }

  Future<void> markConflict({
    required String noteId,
    required String operationId,
  }) async {
    await _database.transaction(() async {
      await (_database.update(_database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(const NotesCompanion(syncStatus: Value('CONFLICT')));
      await (_database.delete(
        _database.syncOutbox,
      )..where((table) => table.operationId.equals(operationId))).go();
    });
  }

  Future<void> applyRemote(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final existing = await (_database.select(
      _database.notes,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final categoryId = payload['categoryId'] as String?;
    final validCategory =
        categoryId != null && await _categoryExists(categoryId)
        ? categoryId
        : null;

    final companion = NotesCompanion(
      id: Value(id),
      title: Value(payload['title'] as String? ?? 'Заметка'),
      contentMarkdown: Value(payload['contentMarkdown'] as String? ?? ''),
      categoryId: Value(validCategory),
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
      await _database.into(_database.notes).insert(companion);
    } else {
      await (_database.update(
        _database.notes,
      )..where((table) => table.id.equals(id))).write(companion);
    }
  }

  Future<void> setSyncStatus(String noteId, String status) async {
    await (_database.update(_database.notes)
          ..where((table) => table.id.equals(noteId)))
        .write(NotesCompanion(syncStatus: Value(status)));
  }

  Future<bool> _categoryExists(String id) async {
    final row = await (_database.select(
      _database.categories,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row != null;
  }

  Future<SyncOutboxData?> _pendingFor(String noteId) async {
    final query = _database.select(_database.syncOutbox)
      ..where((table) => table.entityId.equals(noteId))
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  static Note _domain(NoteRow row, String? categoryName) => Note(
    id: row.id,
    title: row.title,
    contentMarkdown: row.contentMarkdown,
    categoryId: row.categoryId,
    categoryName: categoryName,
    revision: row.revision,
    syncStatus: row.syncStatus,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static String _payload({
    required String title,
    required String contentMarkdown,
    required String categoryId,
  }) => jsonEncode({
    'title': title,
    'contentMarkdown': contentMarkdown,
    'categoryId': categoryId,
  });

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
