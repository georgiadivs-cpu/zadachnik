import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Notes, SyncOutbox, SyncStates, Conflicts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(notes, notes.syncStatus);
        await migrator.addColumn(syncOutbox, syncOutbox.baseRevision);
        await migrator.createTable(syncStates);
        await migrator.createTable(conflicts);
        await _enqueueLocalNotes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _seedCategories();
    },
  );

  /// Заметки, созданные до появления sync, получают операцию в outbox,
  /// иначе после обновления они остались бы навсегда локальными.
  Future<void> _enqueueLocalNotes() async {
    final rows = await select(notes).get();
    for (final row in rows) {
      final existing =
          await (select(syncOutbox)
                ..where((table) => table.entityId.equals(row.id))
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) {
        continue;
      }

      final deleted = row.deletedAt != null;
      await into(syncOutbox).insert(
        SyncOutboxCompanion.insert(
          operationId: const Uuid().v4(),
          entityType: 'NOTE',
          entityId: row.id,
          operationType: deleted ? 'DELETE' : 'CREATE',
          payload: deleted
              ? '{}'
              : jsonEncode({
                  'title': row.title,
                  'contentMarkdown': row.contentMarkdown,
                  'categoryId': row.categoryId,
                }),
          baseRevision: Value(deleted ? row.revision : null),
          createdAt: row.updatedAt,
        ),
      );
    }
  }

  Future<void> _seedCategories() async {
    final existing = await (select(categories)..limit(1)).getSingleOrNull();
    if (existing != null) {
      return;
    }

    final now = DateTime.now().toUtc();
    await batch((batch) {
      batch.insertAll(categories, [
        CategoriesCompanion.insert(
          id: 'work',
          name: 'Работа',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
        CategoriesCompanion.insert(
          id: 'personal',
          name: 'Личное',
          sortOrder: 1,
          createdAt: now,
          updatedAt: now,
        ),
        CategoriesCompanion.insert(
          id: 'family',
          name: 'Семья',
          sortOrder: 2,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
    });
  }

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'zadachnik_client');
}
