import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/auth/data/auth_api.dart';
import 'package:zadachnik_client/features/auth/data/auth_models.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/sync/application/sync_service.dart';
import 'package:zadachnik_client/features/sync/data/sync_api.dart';
import 'package:zadachnik_client/features/sync/data/sync_repository.dart';

const _baseUrl = String.fromEnvironment('SYNC_E2E_BASE_URL');
const _setupToken = String.fromEnvironment('SYNC_E2E_SETUP_TOKEN');
const _deviceId = '11111111-1111-4111-8111-111111111111';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final enabled = _baseUrl.isNotEmpty && _setupToken.isNotEmpty;

  test(
    'NOTE: create → pull на втором клиенте → update → delete',
    () async {
      final auth = DioAuthApi(baseUrl: _baseUrl);
      final email = 'e2e-${DateTime.now().microsecondsSinceEpoch}@example.com';
      final response = await auth.setup(
        setupToken: _setupToken,
        email: email,
        password: 'correct-horse-battery',
        device: const DeviceInfo(
          id: _deviceId,
          name: 'E2E macOS',
          platform: 'MACOS',
        ),
      );
      final session = response.toSession(email);

      final databaseA = AppDatabase.forTesting(NativeDatabase.memory());
      final databaseB = AppDatabase.forTesting(NativeDatabase.memory());
      final notesA = NotesRepository(databaseA);
      final notesB = NotesRepository(databaseB);
      final serviceA = _service(databaseA, notesA, session);
      final serviceB = _service(databaseB, notesB, session);

      try {
        final id = await notesA.create(
          title: 'E2E заметка',
          contentMarkdown: '# Создана клиентом',
          categoryId: 'personal',
        );

        final created = await serviceA.sync();
        expect(created.pushed, 1);
        expect(created.pulled, 1);
        expect((await notesA.findById(id))?.syncStatus, 'SYNCED');
        expect((await databaseA.select(databaseA.syncOutbox).get()), isEmpty);

        final pulled = await serviceB.sync();
        expect(pulled.pulled, greaterThanOrEqualTo(1));
        expect((await notesB.findById(id))?.title, 'E2E заметка');

        final noteA = (await notesA.findById(id))!;
        await notesA.updateLocal(
          note: noteA,
          title: 'E2E обновлена',
          contentMarkdown: '# Обновлено клиентом',
          categoryId: 'work',
        );
        final updated = await serviceA.sync();
        expect(updated.pushed, 1);
        expect((await notesA.findById(id))?.title, 'E2E обновлена');

        await serviceB.sync();
        expect((await notesB.findById(id))?.title, 'E2E обновлена');

        final beforeDeleteA = (await notesA.findById(id))!;
        await notesA.deleteLocal(beforeDeleteA);
        final deleted = await serviceA.sync();
        expect(deleted.pushed, 1);
        expect(await notesA.watchAll().first, isEmpty);

        await serviceB.sync();
        expect(await notesB.watchAll().first, isEmpty);
        final tombstone = await (databaseB.select(
          databaseB.notes,
        )..where((table) => table.id.equals(id))).getSingle();
        expect(tombstone.deletedAt, isNotNull);
      } finally {
        await databaseA.close();
        await databaseB.close();
      }
    },
    skip: enabled
        ? false
        : 'Задайте SYNC_E2E_BASE_URL и SYNC_E2E_SETUP_TOKEN для e2e',
  );
}

SyncService _service(
  AppDatabase database,
  NotesRepository notes,
  Session session,
) => SyncService(
  database: database,
  notes: notes,
  syncRepository: SyncRepository(database),
  api: DioSyncApi(baseUrl: _baseUrl),
  sessionResolver: ({bool force = false}) async => session,
);
