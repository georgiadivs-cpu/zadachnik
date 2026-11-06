import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/calendar/application/calendar_providers.dart';
import 'package:zadachnik_client/features/calendar/application/reminder_coordinator.dart';
import 'package:zadachnik_client/features/calendar/data/reminders_repository.dart';
import 'package:zadachnik_client/features/calendar/domain/task_reminder.dart';
import 'package:zadachnik_client/features/calendar/presentation/calendar_page.dart';
import 'package:zadachnik_client/features/sync/application/sync_controller.dart';
import 'package:zadachnik_client/features/tasks/application/tasks_providers.dart';
import 'package:zadachnik_client/features/tasks/data/lanes_repository.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/lane.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

import '../../auth/fakes.dart';
import '../../calendar/fakes.dart';

void main() {
  late AppDatabase database;
  late LanesRepository lanesRepository;
  late TasksRepository tasks;
  late RemindersRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderCoordinator coordinator;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    lanesRepository = LanesRepository(database);
    tasks = TasksRepository(database);
    reminders = RemindersRepository(database);
    scheduler = FakeReminderScheduler();
    coordinator = ReminderCoordinator(
      reminders: reminders,
      tasks: tasks,
      scheduler: scheduler,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<Lane>> loadLanes() async {
    final rows = await (database.select(database.lanes)
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

  TaskDraft draftOn(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return TaskDraft(
      title: 'Задача календаря',
      description: '',
      laneId: DefaultLanes.newLaneId,
      categoryId: 'work',
      priority: 'NORMAL',
      plannedStartAt: local.toUtc(),
      plannedEndAt: local.toUtc(),
      actualStartAt: null,
      actualEndAt: null,
    );
  }

  Widget app({
    required List<Lane> lanes,
    required List<Task> tasksData,
    required List<TaskReminder> remindersData,
  }) {
    return ProviderScope(
      overrides: [
        lanesRepositoryProvider.overrideWithValue(lanesRepository),
        tasksRepositoryProvider.overrideWithValue(tasks),
        remindersRepositoryProvider.overrideWithValue(reminders),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderCoordinatorProvider.overrideWithValue(coordinator),
        lanesProvider.overrideWith((ref) => Stream.value(lanes)),
        tasksProvider.overrideWith((ref) => Stream.value(tasksData)),
        remindersProvider.overrideWith((ref) => Stream.value(remindersData)),
        syncControllerProvider.overrideWith(NoopSyncController.new),
      ],
      child: const MaterialApp(home: CalendarPage()),
    );
  }

  testWidgets('показывает задачи по плановой дате и напоминания', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final id = await tasks.create(draftOn(now));
    final task = (await tasks.findById(id))!;
    final reminder = await reminders.saveForTask(
      id,
      DateTime(now.year, now.month, now.day, 23, 59).toUtc(),
    );
    final lanes = await loadLanes();

    await tester.pumpWidget(
      app(lanes: lanes, tasksData: [task], remindersData: [reminder!]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Задача календаря'), findsWidgets);
    expect(find.byIcon(Icons.notifications), findsWidgets);
    expect(find.textContaining('1 задач'), findsOneWidget);
    expect(find.textContaining('1 напоминаний'), findsOneWidget);
  });

  testWidgets('открывает задачу и добавляет напоминание', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final id = await tasks.create(draftOn(now));
    final task = (await tasks.findById(id))!;
    final lanes = await loadLanes();

    await tester.pumpWidget(
      app(lanes: lanes, tasksData: [task], remindersData: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Задача календаря'), findsWidgets);
    await tester.tap(find.text('Задача календаря').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('taskTitleField')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('addReminderButton')));
    await tester.tap(find.byKey(const Key('addReminderButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('taskSaveButton')));
    await tester.pumpAndSettle();

    expect(await reminders.findForTask(id), isNotNull);
    expect(scheduler.scheduled, hasLength(1));
  });

  testWidgets('календарь помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final now = DateTime.now();
    final id = await tasks.create(draftOn(now));
    final task = (await tasks.findById(id))!;
    final lanes = await loadLanes();

    await tester.pumpWidget(
      app(lanes: lanes, tasksData: [task], remindersData: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Календарь'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
