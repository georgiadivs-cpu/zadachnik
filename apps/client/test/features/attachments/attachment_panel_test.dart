import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/attachments/application/attachment_coordinator.dart';
import 'package:zadachnik_client/features/attachments/application/attachments_providers.dart';
import 'package:zadachnik_client/features/attachments/data/attachments_repository.dart';
import 'package:zadachnik_client/features/attachments/domain/attachment.dart';
import 'package:zadachnik_client/features/attachments/presentation/attachment_panel.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';

import '../../auth/fakes.dart';
import '../../attachments/fakes.dart';

void main() {
  late AppDatabase database;
  late AttachmentsRepository repository;
  late FakeAttachmentFileStore fileStore;
  late FakeAttachmentApi api;
  late AttachmentCoordinator coordinator;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AttachmentsRepository(database);
    fileStore = FakeAttachmentFileStore();
    api = FakeAttachmentApi();
    final session = Session(
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

  Widget app(List<Attachment> items) {
    return ProviderScope(
      overrides: [
        attachmentsRepositoryProvider.overrideWithValue(repository),
        attachmentFileStoreProvider.overrideWithValue(fileStore),
        attachmentApiProvider.overrideWithValue(api),
        attachmentCoordinatorProvider.overrideWithValue(coordinator),
        attachmentsProvider.overrideWith((ref, owner) => Stream.value(items)),
        syncControllerProvider.overrideWith(NoopSyncController.new),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AttachmentPanel(
            ownerType: AttachmentOwnerType.note,
            ownerId: 'note-1',
          ),
        ),
      ),
    );
  }

  testWidgets('показывает файлы, статусы и ошибку', (tester) async {
    final ready = await repository.createLocal(
      id: 'a1',
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      fileName: 'photo.png',
      mimeType: 'image/png',
      sizeBytes: 2048,
      sha256: 'a' * 64,
      localPath: '/fake/a1',
    );
    final error = await repository.createLocal(
      id: 'a2',
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      fileName: 'contract.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      sha256: 'b' * 64,
      localPath: '/fake/a2',
    );
    await repository.markReady(
      id: ready.id,
      revision: 1,
      sha256: ready.sha256,
      mimeType: ready.mimeType,
      sizeBytes: ready.sizeBytes,
    );
    await repository.markError(error.id, 'Сервер недоступен');
    final items = [
      (await repository.findById('a1'))!,
      (await repository.findById('a2'))!,
    ];

    await tester.pumpWidget(app(items));
    await tester.pumpAndSettle();

    expect(find.text('Вложения'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Ошибка'), findsOneWidget);
    expect(find.text('Сервер недоступен'), findsOneWidget);
  });

  testWidgets('удаляет вложение после подтверждения', (tester) async {
    await repository.createLocal(
      id: 'a1',
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      fileName: 'photo.png',
      mimeType: 'image/png',
      sizeBytes: 2048,
      sha256: 'a' * 64,
      localPath: '/fake/a1',
    );
    await repository.markReady(
      id: 'a1',
      revision: 1,
      sha256: 'a' * 64,
      mimeType: 'image/png',
      sizeBytes: 2048,
    );
    final item = (await repository.findById('a1'))!;

    await tester.pumpWidget(app([item]));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить вложение?'), findsOneWidget);
    await tester.tap(find.text('Удалить'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(api.deletes, contains('a1'));
    expect(await repository.findById('a1'), isNull);
    expect(api.deletes, contains('a1'));
  });

  testWidgets('панель помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final item = await repository.createLocal(
      id: 'a1',
      ownerType: AttachmentOwnerType.note,
      ownerId: 'note-1',
      fileName: 'document-with-a-very-long-name.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 2048,
      sha256: 'a' * 64,
      localPath: '/fake/a1',
    );

    await tester.pumpWidget(app([item]));
    await tester.pumpAndSettle();

    expect(find.text('document-with-a-very-long-name.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
