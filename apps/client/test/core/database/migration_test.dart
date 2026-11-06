import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';

void main() {
  test('миграция v1 → v6 сохраняет заметку и ставит её в outbox', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) async {
          raw.execute('''
          CREATE TABLE categories (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
          raw.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            content_markdown TEXT NOT NULL DEFAULT '',
            category_id TEXT REFERENCES categories (id),
            revision INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER
          )
        ''');
          raw.execute('''
          CREATE TABLE sync_outbox (
            operation_id TEXT NOT NULL PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
          raw.execute(
            "INSERT INTO categories VALUES ('personal', 'Личное', 1, 1762344000, 1762344000)",
          );
          raw.execute(
            "INSERT INTO notes VALUES ('legacy-note', 'Старая заметка', '# Текст', "
            "'personal', 1, 1762344000, 1762344000, NULL)",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );

    try {
      final notes = await database.select(database.notes).get();
      expect(notes, hasLength(1));
      expect(notes.single.title, 'Старая заметка');
      expect(notes.single.syncStatus, 'PENDING');

      final operations = await database.select(database.syncOutbox).get();
      expect(operations, hasLength(1));
      final operation = operations.single;
      expect(operation.entityId, 'legacy-note');
      expect(operation.operationType, 'CREATE');
      expect(operation.baseRevision, isNull);
      final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
      expect(payload['title'], 'Старая заметка');
      expect(payload['contentMarkdown'], '# Текст');
      expect(payload['categoryId'], 'personal');

      expect(await database.select(database.syncStates).get(), isEmpty);
      expect(await database.select(database.conflicts).get(), isEmpty);
      expect(await database.select(database.lanes).get(), hasLength(4));
      expect(await database.select(database.tasks).get(), isEmpty);
      expect(await database.select(database.taskReminders).get(), isEmpty);
      expect(await database.select(database.attachments).get(), isEmpty);
      expect(await database.select(database.aiActions).get(), isEmpty);
      expect(database.schemaVersion, 6);
    } finally {
      await database.close();
    }
  });
}
