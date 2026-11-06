import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/auth/data/auth_api.dart';
import 'package:zadachnik_client/features/attachments/application/attachment_coordinator.dart';
import 'package:zadachnik_client/features/attachments/data/attachment_api.dart';
import 'package:zadachnik_client/features/attachments/data/attachment_file_store.dart';
import 'package:zadachnik_client/features/attachments/data/attachments_repository.dart';
import 'package:zadachnik_client/features/attachments/domain/attachment.dart';
import 'package:zadachnik_client/features/calendar/data/reminders_repository.dart';
import 'package:zadachnik_client/features/auth/data/auth_models.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/sync/application/sync_service.dart';
import 'package:zadachnik_client/features/sync/data/sync_api.dart';
import 'package:zadachnik_client/features/sync/data/sync_repository.dart';
import 'package:zadachnik_client/features/tasks/data/lanes_repository.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/lane.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

const _baseUrl = String.fromEnvironment('SYNC_E2E_BASE_URL');
const _setupToken = String.fromEnvironment('SYNC_E2E_SETUP_TOKEN');
const _deviceId = '11111111-1111-4111-8111-111111111111';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final enabled = _baseUrl.isNotEmpty && _setupToken.isNotEmpty;

  test(
    'NOTE + TASK + REMINDER + ATTACHMENT: sync и файлы',
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
      final tasksA = TasksRepository(databaseA);
      final tasksB = TasksRepository(databaseB);
      final lanesA = LanesRepository(databaseA);
      final lanesB = LanesRepository(databaseB);
      final remindersA = RemindersRepository(databaseA);
      final remindersB = RemindersRepository(databaseB);
      final attachmentsA = AttachmentsRepository(databaseA);
      final attachmentsB = AttachmentsRepository(databaseB);
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

        final fileStoreA = _TempAttachmentFileStore();
        final fileStoreB = _TempAttachmentFileStore();
        final coordinatorA = AttachmentCoordinator(
          repository: attachmentsA,
          fileStore: fileStoreA,
          api: DioAttachmentApi(baseUrl: _baseUrl),
          sessionResolver: ({bool force = false}) async => session,
        );
        final coordinatorB = AttachmentCoordinator(
          repository: attachmentsB,
          fileStore: fileStoreB,
          api: DioAttachmentApi(baseUrl: _baseUrl),
          sessionResolver: ({bool force = false}) async => session,
        );
        final png = pngBytes();
        final attachment = await coordinatorA.addFile(
          ownerType: AttachmentOwnerType.note,
          ownerId: id,
          file: XFile.fromData(
            Uint8List.fromList(png),
            path: 'e2e.png',
            name: 'e2e.png',
            mimeType: 'image/png',
          ),
        );
        await coordinatorA.reconcile();
        expect(
          (await attachmentsA.findById(attachment.id))?.uploadStatus,
          'READY',
        );
        await serviceB.sync();
        await coordinatorB.reconcile();
        final downloaded = await attachmentsB.findById(attachment.id);
        expect(downloaded?.uploadStatus, 'READY');
        expect(downloaded?.localPath, isNotNull);
        expect(File(downloaded!.localPath!).readAsBytesSync(), png);

        final ready = (await attachmentsA.findById(attachment.id))!;
        await coordinatorA.deleteAttachment(ready);
        await serviceB.sync();
        await coordinatorB.reconcile();
        expect(await attachmentsB.findById(attachment.id), isNull);
        await fileStoreA.dispose();
        await fileStoreB.dispose();

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

        final lanesBefore = await lanesA.watchAll().first;
        await lanesA.saveConfiguration([
          for (final lane in lanesBefore)
            LaneDraft(id: lane.id, name: lane.name),
          const LaneDraft(name: 'E2E дорожка'),
        ]);
        final laneSync = await serviceA.sync();
        expect(laneSync.pushed, 1);
        await serviceB.sync();
        final lanesOnB = await lanesB.watchAll().first;
        expect(lanesOnB, hasLength(5));
        final e2eLane = lanesOnB.firstWhere(
          (lane) => lane.name == 'E2E дорожка',
        );

        final taskId = await tasksA.create(
          TaskDraft(
            title: 'E2E задача',
            description: 'Создана клиентом',
            laneId: e2eLane.id,
            categoryId: 'work',
            priority: 'HIGH',
            plannedStartAt: DateTime.utc(2026, 11, 6),
            plannedEndAt: DateTime.utc(2026, 11, 8),
            actualStartAt: null,
            actualEndAt: null,
          ),
        );
        final taskSync = await serviceA.sync();
        expect(taskSync.pushed, 1);
        await serviceB.sync();
        expect((await tasksB.findById(taskId))?.title, 'E2E задача');
        expect((await tasksB.findById(taskId))?.laneId, e2eLane.id);

        final taskOnA = (await tasksA.findById(taskId))!;
        await tasksA.moveToLane(taskOnA, DefaultLanes.inProgressLaneId);
        await serviceA.sync();
        await serviceB.sync();
        expect(
          (await tasksB.findById(taskId))?.laneId,
          DefaultLanes.inProgressLaneId,
        );

        await remindersA.saveForTask(taskId, DateTime.utc(2030, 1, 10, 14));
        await serviceA.sync();
        await serviceB.sync();
        expect(
          (await remindersB.findForTask(taskId))?.remindAt,
          DateTime.utc(2030, 1, 10, 14),
        );

        await remindersA.saveForTask(taskId, null);
        await serviceA.sync();
        await serviceB.sync();
        expect(await remindersB.findForTask(taskId), isNull);

        final movedTask = (await tasksA.findById(taskId))!;
        await tasksA.setCancelled(movedTask, true);
        await serviceA.sync();
        await serviceB.sync();
        expect((await tasksB.findById(taskId))?.isCancelled, isTrue);
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

List<int> pngBytes() => [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
];

class _TempAttachmentFileStore implements AttachmentFileStore {
  _TempAttachmentFileStore()
    : _directory = Directory.systemTemp.createTempSync('zadachnik-e2e-');

  final Directory _directory;

  @override
  Future<bool> exists(String path) async => File(path).exists();

  @override
  Future<StoredAttachmentFile> store(String id, XFile file) async {
    final bytes = await file.readAsBytes();
    final path = '${_directory.path}/$id';
    await File(path).writeAsBytes(bytes);
    return StoredAttachmentFile(
      path: path,
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<String> storeBytes({
    required String id,
    required List<int> bytes,
    required String expectedSha256,
  }) async {
    final digest = sha256.convert(bytes).toString();
    if (digest != expectedSha256) {
      throw StateError('checksum mismatch');
    }
    final path = '${_directory.path}/$id';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  @override
  Future<void> deletePath(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  Future<void> dispose() async {
    if (_directory.existsSync()) {
      _directory.deleteSync(recursive: true);
    }
  }
}

SyncService _service(
  AppDatabase database,
  NotesRepository notes,
  Session session,
) => SyncService(
  database: database,
  notes: notes,
  tasks: TasksRepository(database),
  lanes: LanesRepository(database),
  reminders: RemindersRepository(database),
  attachments: AttachmentsRepository(database),
  syncRepository: SyncRepository(database),
  api: DioSyncApi(baseUrl: _baseUrl),
  sessionResolver: ({bool force = false}) async => session,
);
