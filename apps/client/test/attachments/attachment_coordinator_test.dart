import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/attachments/application/attachment_coordinator.dart';
import 'package:zadachnik_client/features/attachments/data/attachment_api.dart';
import 'package:zadachnik_client/features/attachments/data/attachments_repository.dart';
import 'package:zadachnik_client/features/attachments/domain/attachment.dart';

import 'fakes.dart';

void main() {
  late AppDatabase database;
  late AttachmentsRepository repository;
  late FakeAttachmentFileStore fileStore;
  late FakeAttachmentApi api;
  late AttachmentCoordinator coordinator;
  late Session session;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AttachmentsRepository(database);
    fileStore = FakeAttachmentFileStore();
    api = FakeAttachmentApi();
    session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'access',
      refreshToken: 'refresh',
      accessExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    coordinator = AttachmentCoordinator(
      repository: repository,
      fileStore: fileStore,
      api: api,
      sessionResolver: ({bool force = false}) async => session,
    );
  });

  tearDown(() async {
    await database.close();
    await fileStore.dispose();
  });

  XFile file(String name, List<int> bytes) => XFile.fromData(
    Uint8List.fromList(bytes),
    path: name,
    name: name,
    mimeType: AttachmentRules.mimeForName(name),
  );

  test('добавляет файл локально и загружает его', () async {
    final attachment = await coordinator.addFile(
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      file: file('photo.png', [1, 2, 3, 4]),
    );

    expect(attachment.uploadStatus, 'PENDING');
    expect(attachment.localPath, isNotNull);
    expect(await fileStore.exists(attachment.localPath!), isTrue);

    await coordinator.reconcile();

    final saved = await repository.findById(attachment.id);
    expect(saved?.uploadStatus, 'READY');
    expect(saved?.serverRevision, 1);
    expect(api.uploads, contains(attachment.id));
  });

  test('скачивает серверное вложение', () async {
    final bytes = [5, 6, 7, 8];
    final sha = sha256.convert(bytes).toString();
    api.remoteFiles['attachment-remote'] = bytes;
    await repository.applyRemote({
      'id': 'attachment-remote',
      'ownerType': 'NOTE',
      'ownerId': 'note-1',
      'fileName': 'remote.pdf',
      'mimeType': 'application/pdf',
      'sizeBytes': bytes.length,
      'sha256': sha,
      'revision': 2,
      'createdAt': '2026-11-06T10:00:00Z',
      'updatedAt': '2026-11-06T10:00:00Z',
      'deletedAt': null,
    });

    await coordinator.reconcile();

    final saved = await repository.findById('attachment-remote');
    expect(saved?.uploadStatus, 'READY');
    expect(saved?.localPath, isNotNull);
    expect(api.downloads, contains('attachment-remote'));
  });

  test('удаляет загруженный файл с сервера и устройства', () async {
    final attachment = await coordinator.addFile(
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      file: file('photo.png', [1, 2, 3, 4]),
    );
    await coordinator.reconcile();
    final ready = (await repository.findById(attachment.id))!;

    await coordinator.deleteAttachment(ready);

    expect(api.deletes, contains(attachment.id));
    expect(await repository.findById(attachment.id), isNull);
    expect(await fileStore.exists(ready.localPath!), isFalse);
  });

  test('удалённый tombstone удаляет локальный файл', () async {
    final attachment = await coordinator.addFile(
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      file: file('photo.png', [1, 2, 3, 4]),
    );
    await coordinator.reconcile();
    final ready = (await repository.findById(attachment.id))!;

    await repository.applyRemote({
      'id': attachment.id,
      'ownerType': 'NOTE',
      'ownerId': 'note-1',
      'fileName': 'photo.png',
      'mimeType': 'image/png',
      'sizeBytes': ready.sizeBytes,
      'sha256': ready.sha256,
      'revision': 2,
      'createdAt': '2026-11-06T10:00:00Z',
      'updatedAt': '2026-11-06T11:00:00Z',
      'deletedAt': '2026-11-06T11:00:00Z',
    });
    await coordinator.reconcile();

    expect(await repository.findById(attachment.id), isNull);
    expect(await fileStore.exists(ready.localPath!), isFalse);
  });

  test('ошибка загрузки сохраняет файл для повтора', () async {
    final attachment = await coordinator.addFile(
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      file: file('photo.png', [1, 2, 3, 4]),
    );
    api.uploadFailure = const AttachmentApiFailure(
      code: 'NETWORK_ERROR',
      message: 'Сервер недоступен',
      network: true,
    );

    await coordinator.reconcile();

    final failed = await repository.findById(attachment.id);
    expect(failed?.uploadStatus, 'ERROR');
    expect(failed?.localPath, isNotNull);
    expect(await fileStore.exists(failed!.localPath!), isTrue);
  });

  test('отклоняет неразрешённый тип файла', () async {
    expect(
      () => coordinator.addFile(
        ownerType: AttachmentOwnerType.note,
        ownerId: 'note-1',
        file: file('archive.zip', [1, 2, 3]),
      ),
      throwsArgumentError,
    );
  });
}
