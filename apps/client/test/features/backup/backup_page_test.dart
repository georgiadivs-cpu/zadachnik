import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/app/app.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/auth/session_store.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/auth/application/auth_controller.dart';
import 'package:zadachnik_client/features/backup/application/backup_providers.dart';
import 'package:zadachnik_client/features/backup/data/backup_api.dart';
import 'package:zadachnik_client/features/backup/data/backup_status_store.dart';
import 'package:zadachnik_client/features/backup/data/device_snapshot_service.dart';
import 'package:zadachnik_client/features/backup/domain/backup_models.dart';
import 'package:zadachnik_client/features/backup/presentation/backup_page.dart';
import 'package:zadachnik_client/features/backup/presentation/backup_status_bar.dart';

import 'fakes.dart';

class _MemoryBackupStatusStore extends BackupStatusStore {
  BackupStatusSnapshot? value;

  @override
  Future<BackupStatusSnapshot?> read() async => value;

  @override
  Future<void> write(BackupStatusSnapshot status) async => value = status;
}

class _FakeSnapshotService extends DeviceSnapshotService {
  _FakeSnapshotService(super.database);

  @override
  Future<PreparedSnapshot> prepare() async => PreparedSnapshot(
    path: '/tmp/fake-snapshot.db',
    sha256: List.filled(64, 'c').join(),
    sizeBytes: 1024,
    schemaVersion: 6,
  );

  @override
  Future<void> discard(PreparedSnapshot snapshot) async {}
}

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late FakeBackupApi api;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup-test');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    api = FakeBackupApi();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ProviderContainer> createContainer() async {
    final now = DateTime.now().toUtc();
    final store = InMemorySessionStore(
      session: Session(
        email: 'owner@example.com',
        userId: 'user-1',
        deviceId: 'device-1',
        accessToken: 'access',
        refreshToken: 'refresh',
        accessExpiresAt: now.add(const Duration(minutes: 15)),
        refreshExpiresAt: now.add(const Duration(days: 30)),
      ),
      deviceId: 'device-1',
    );
    final container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        backupApiProvider.overrideWithValue(api),
        backupStatusStoreProvider.overrideWithValue(_MemoryBackupStatusStore()),
        deviceSnapshotServiceProvider.overrideWithValue(
          _FakeSnapshotService(database),
        ),
      ],
    );
    await container.read(authControllerProvider.notifier).bootstrap();
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BackupPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('показывает статус, историю и политику хранения', (tester) async {
    final container = await createContainer();
    await pumpPage(tester, container);

    expect(api.statusCalls, greaterThan(0));
    expect(container.read(backupControllerProvider).status, isNotNull);
    expect(find.text('Последняя копия проверена'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Снимки устройств'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('История'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Диск и хранение'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('7 последних'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Шифрование и приватность'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Восстановление'), findsOneWidget);
  });

  testWidgets('проверяет выбранную копию', (tester) async {
    final container = await createContainer();
    await pumpPage(tester, container);

    await tester.tap(find.byKey(const Key('backupVerifyButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.verifyCalls, 1);
    expect(find.textContaining('Проверка копии завершена'), findsOneWidget);
  });

  testWidgets('загружает снимок устройства', (tester) async {
    final container = await createContainer();
    await pumpPage(tester, container);

    await tester.tap(find.byKey(const Key('backupUploadSnapshotButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.uploadCalls, 1);
    expect(find.textContaining('Снимок устройства загружен'), findsOneWidget);
  });

  testWidgets('показывает ошибку конфигурации', (tester) async {
    api.statusResponse = makeStatus(configured: false);
    final container = await createContainer();
    await pumpPage(tester, container);

    expect(find.textContaining('BACKUP_AGE_IDENTITY'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('backupStartButton')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('показывает offline-состояние', (tester) async {
    api.failure = const BackupFailure(
      code: 'NETWORK_ERROR',
      message: 'Сервер недоступен',
      network: true,
    );
    final container = await createContainer();
    await pumpPage(tester, container);

    expect(find.textContaining('Нет связи с сервером'), findsOneWidget);
  });

  testWidgets('полоса статуса открывает резервные копии', (tester) async {
    final container = await createContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          builder: (context, child) =>
              BackupStatusHost(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: Center(child: Text('Экран заметок'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Экран заметок'), findsOneWidget);
    expect(find.textContaining('Бэкап:'), findsOneWidget);

    await tester.tap(find.textContaining('Бэкап:'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Резервные копии'), findsOneWidget);
  });

  testWidgets('не переполняется на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await createContainer();
    await pumpPage(tester, container);

    await tester.scrollUntilVisible(
      find.text('Диск и хранение'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  });

  test('запускает backup через контроллер', () async {
    final container = await createContainer();
    final controller = container.read(backupControllerProvider.notifier);
    await controller.initialize();

    final error = await controller.startBackup();

    expect(error, isNull);
    expect(api.startCalls, 1);
    expect(container.read(backupControllerProvider).status?.running, isTrue);
  });

  test('экспортирует согласованный снимок SQLite', () async {
    final service = DeviceSnapshotService(database, tempDirectory: tempDir);
    final snapshot = await service.prepare();

    expect(await File(snapshot.path).exists(), isTrue);
    expect(snapshot.sizeBytes, greaterThan(0));
    expect(snapshot.sha256, hasLength(64));
    expect(snapshot.schemaVersion, 6);

    await service.discard(snapshot);
    expect(await File(snapshot.path).exists(), isFalse);
  });
}
