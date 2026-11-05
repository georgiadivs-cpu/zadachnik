import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' hide Note;
import '../domain/note.dart';

/// Локальные операции с заметками и запись в outbox.
///
/// Заметка сохраняется локально до любой попытки синхронизации.
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
        return Note(
          id: note.id,
          title: note.title,
          contentMarkdown: note.contentMarkdown,
          categoryId: note.categoryId,
          categoryName: category?.name,
          revision: note.revision,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
        );
      }).toList(),
    );
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
              payload: jsonEncode({
                'title': normalizedTitle,
                'contentMarkdown': contentMarkdown,
                'categoryId': categoryId,
              }),
              createdAt: now,
            ),
          );
    });

    return id;
  }
}
