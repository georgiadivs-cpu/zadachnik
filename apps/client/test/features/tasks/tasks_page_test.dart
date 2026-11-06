import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/attachments/application/attachment_coordinator.dart';
import 'package:zadachnik_client/features/attachments/application/attachments_providers.dart';
import 'package:zadachnik_client/features/attachments/data/attachments_repository.dart';
import 'package:zadachnik_client/features/calendar/application/calendar_providers.dart';
import 'package:zadachnik_client/features/calendar/application/reminder_coordinator.dart';
import 'package:zadachnik_client/features/calendar/data/reminders_repository.dart';
import 'package:zadachnik_client/features/calendar/domain/task_reminder.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';
import 'package:zadachnik_client/features/tasks/application/tasks_providers.dart';
import 'package:zadachnik_client/features/tasks/data/lanes_repository.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/lane.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';
import 'package:zadachnik_client/features/tasks/presentation/tasks_page.dart';

import '../../auth/fakes.dart';
import '../../attachments/fakes.dart';
import '../../calendar/fakes.dart';

void main() {
  late AppDatabase database;
  late LanesRepository lanes;
  late TasksRepository tasks;
  late RemindersRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderCoordinator coordinator;
  late AttachmentsRepository attachments;
  late FakeAttachmentFileStore attachmentFiles;
  late FakeAttachmentApi attachmentApi;
  late AttachmentCoordinator attachmentCoordinator;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    lanes = LanesRepository(database);
    tasks = TasksRepository(database);
    reminders = RemindersRepository(database);
    scheduler = FakeReminderScheduler();
    coordinator = ReminderCoordinator(
      reminders: reminders,
      tasks: tasks,
      scheduler: scheduler,
    );
    attachments = AttachmentsRepository(database);
    attachmentFiles = FakeAttachmentFileStore();
    attachmentApi = FakeAttachmentApi();
    final session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'access',
      refreshToken: 'refresh',
      accessExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    attachmentCoordinator = AttachmentCoordinator(
      repository: attachments,
      fileStore: attachmentFiles,
      api: attachmentApi,
      sessionResolver: ({bool force = false}) async => session,
    );
  });

  tearDown(() async {
    await database.close();
    await attachmentFiles.dispose();
  });

  Future<List<Lane>> loadLanes() async {
    final rows =
        await (database.select(database.lanes)
              ..where((table) => table.deletedAt.isNull())
              ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
            .get();
    return rows
        .map(
          (row) => Lane(
            id: row.id,
            name: row.name,
            sortOrder: row.sortOrder,
            revision: row.revision,
            syncStatus: row.syncStatus,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  TaskDraft draft(String laneId, {String title = 'Задача'}) => TaskDraft(
    title: title,
    description: 'Описание задачи',
    laneId: laneId,
    categoryId: 'work',
    priority: 'HIGH',
    plannedStartAt: DateTime.utc(2026, 11, 6),
    plannedEndAt: DateTime.utc(2026, 11, 8),
    actualStartAt: null,
    actualEndAt: null,
  );

  Widget app({
    required List<Lane> lanesData,
    required List<Task> tasksData,
    List<TaskReminder> remindersData = const [],
  }) {
    return ProviderScope(
      overrides: [
        lanesRepositoryProvider.overrideWithValue(lanes),
        tasksRepositoryProvider.overrideWithValue(tasks),
        remindersRepositoryProvider.overrideWithValue(reminders),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderCoordinatorProvider.overrideWithValue(coordinator),
        attachmentsRepositoryProvider.overrideWithValue(attachments),
        attachmentFileStoreProvider.overrideWithValue(attachmentFiles),
        attachmentApiProvider.overrideWithValue(attachmentApi),
        attachmentCoordinatorProvider.overrideWithValue(attachmentCoordinator),
        attachmentsProvider.overrideWith(
          (ref, owner) => Stream.value(const []),
        ),
        lanesProvider.overrideWith((ref) => Stream.value(lanesData)),
        tasksProvider.overrideWith((ref) => Stream.value(tasksData)),
        remindersProvider.overrideWith((ref) => Stream.value(remindersData)),
        syncControllerProvider.overrideWith(NoopSyncController.new),
      ],
      child: const MaterialApp(home: TasksPage()),
    );
  }

  testWidgets('показывает дорожки и создаёт задачу', (tester) async {
    final lanesData = await loadLanes();
    await tester.pumpWidget(app(lanesData: lanesData, tasksData: const []));
    await tester.pumpAndSettle();

    expect(find.text('Новые'), findsOneWidget);
    expect(find.text('В работе'), findsOneWidget);
    expect(find.text('Проверка'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('taskTitleField')),
      'Новая задача',
    );
    await tester.tap(find.byKey(const Key('taskSaveButton')));
    await tester.pumpAndSettle();

    final rows = await database.select(database.tasks).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, 'Новая задача');
    expect(rows.single.laneId, DefaultLanes.newLaneId);
  });

  testWidgets('перемещает задачу через меню', (tester) async {
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = (await tasks.findById(id))!;
    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [task]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переместить: В работе'));
    await tester.pumpAndSettle();

    final moved = await tasks.findById(id);
    expect(moved?.laneId, DefaultLanes.inProgressLaneId);
    final history = await database.select(database.taskStatusHistory).get();
    expect(history, hasLength(2));
  });

  testWidgets('отменяет задачу через меню', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = (await tasks.findById(id))!;
    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [task]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить задачу'));
    await tester.pumpAndSettle();

    final cancelled = await tasks.findById(id);
    expect(cancelled?.isCancelled, isTrue);
  });

  testWidgets('показывает отменённые в отдельном блоке', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final active = (await tasks.findById(id))!;
    await tasks.setCancelled(active, true);
    final cancelled = (await tasks.findById(id))!;

    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [cancelled]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменённые'));
    await tester.pumpAndSettle();

    expect(find.text('Отменённые'), findsWidgets);
    expect(find.text('Отменена'), findsOneWidget);
    expect(find.text('Нет отменённых задач'), findsNothing);
  });

  testWidgets('возвращает отменённую задачу в работу', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final active = (await tasks.findById(id))!;
    await tasks.setCancelled(active, true);
    final cancelled = (await tasks.findById(id))!;
    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [cancelled]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отменённые'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуть в работу'));
    await tester.pumpAndSettle();

    final restored = await tasks.findById(id);
    expect(restored?.isCancelled, isFalse);
  });

  testWidgets('настраивает название и добавляет дорожку', (tester) async {
    final lanesData = await loadLanes();
    await tester.pumpWidget(app(lanesData: lanesData, tasksData: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('laneSettingsButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('laneName0')), 'Входящие');
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('laneName4')), 'Идеи');
    await tester.tap(find.byKey(const Key('saveLanesButton')));
    await tester.pumpAndSettle();

    final configured = await loadLanes();
    expect(configured, hasLength(5));
    expect(configured.first.name, 'Входящие');
    expect(configured.last.name, 'Идеи');
  });

  testWidgets('показывает напоминание на карточке', (tester) async {
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = (await tasks.findById(id))!;
    final reminder = await reminders.saveForTask(
      id,
      DateTime.utc(2030, 1, 10, 14),
    );

    await tester.pumpWidget(
      app(lanesData: lanesData, tasksData: [task], remindersData: [reminder!]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Напоминание'), findsOneWidget);
  });

  testWidgets('открывает панель вложений из карточки', (tester) async {
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = (await tasks.findById(id))!;

    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [task]));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вложения'));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет вложений'), findsOneWidget);
  });

  testWidgets('доска помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanesData = await loadLanes();
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = (await tasks.findById(id))!;

    await tester.pumpWidget(app(lanesData: lanesData, tasksData: [task]));
    await tester.pumpAndSettle();

    expect(find.text('Задача'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
