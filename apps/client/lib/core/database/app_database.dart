import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Notes, SyncOutbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _seedCategories();
    },
  );

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
