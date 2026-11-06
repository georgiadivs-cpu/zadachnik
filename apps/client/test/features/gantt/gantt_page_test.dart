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
import 'package:zadachnik_client/features/gantt/presentation/gantt_page.dart';
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

  TaskDraft draft({
    required String title,
    required String categoryId,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
  }) => TaskDraft(
    title: title,
    description: '',
    laneId: DefaultLanes.newLaneId,
    categoryId: categoryId,
    priority: 'NORMAL',
    plannedStartAt: plannedStart,
    plannedEndAt: plannedEnd,
    actualStartAt: actualStart,
    actualEndAt: actualEnd,
  );

  Widget app({required List<Lane> lanes, required List<Task> tasksData}) {
    return ProviderScope(
      overrides: [
        lanesRepositoryProvider.overrideWithValue(lanesRepository),
        tasksRepositoryProvider.overrideWithValue(tasks),
        remindersRepositoryProvider.overrideWithValue(reminders),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderCoordinatorProvider.overrideWithValue(coordinator),
        lanesProvider.overrideWith((ref) => Stream.value(lanes)),
        tasksProvider.overrideWith((ref) => Stream.value(tasksData)),
        remindersProvider.overrideWith((ref) => Stream.value(const [])),
        syncControllerProvider.overrideWith(NoopSyncController.new),
      ],
      child: MaterialApp(
        home: GanttPage(
          initialDate: DateTime(2026, 11, 6),
          today: DateTime(2026, 11, 6),
        ),
      ),
    );
  }

  Future<List<Task>> seedTasks() async {
    final overdueId = await tasks.create(
      draft(
        title: 'Просроченная задача',
        categoryId: 'work',
        plannedStart: DateTime(2026, 11, 1),
        plannedEnd: DateTime(2026, 11, 4),
        actualStart: DateTime(2026, 11, 1),
      ),
    );
    final personalId = await tasks.create(
      draft(
        title: 'Личная задача',
        categoryId: 'personal',
        plannedStart: DateTime(2026, 11, 3),
        plannedEnd: DateTime(2026, 11, 10),
        actualStart: DateTime(2026, 11, 3),
        actualEnd: DateTime(2026, 11, 5),
      ),
    );
    return [
      (await tasks.findById(overdueId))!,
      (await tasks.findById(personalId))!,
    ];
  }

  testWidgets('показывает план, факт и просрочку', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanes = await loadLanes();
    final tasksData = await seedTasks();

    await tester.pumpWidget(app(lanes: lanes, tasksData: tasksData));
    await tester.pumpAndSettle();

    expect(find.text('Просроченная задача'), findsOneWidget);
    expect(find.text('Личная задача'), findsOneWidget);
    expect(find.text('Просрочено'), findsOneWidget);
    expect(find.byKey(Key('ganttPlan-${tasksData.first.id}')), findsOneWidget);
    expect(
      find.byKey(Key('ganttActual-${tasksData.first.id}')),
      findsOneWidget,
    );
  });

  testWidgets('фильтрует задачи и скрывает фактические полосы', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanes = await loadLanes();
    final tasksData = await seedTasks();

    await tester.pumpWidget(app(lanes: lanes, tasksData: tasksData));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ganttFilter-work')));
    await tester.pumpAndSettle();
    expect(find.text('Просроченная задача'), findsOneWidget);
    expect(find.text('Личная задача'), findsNothing);

    await tester.tap(find.byKey(const Key('ganttActualToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('ganttActual-${tasksData.first.id}')), findsNothing);
  });

  testWidgets('переключает масштаб и открывает задачу', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanes = await loadLanes();
    final tasksData = await seedTasks();

    await tester.pumpWidget(app(lanes: lanes, tasksData: tasksData));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ganttScaleMonth')));
    await tester.pumpAndSettle();
    expect(find.textContaining('май 2026'), findsOneWidget);

    await tester.tap(find.byKey(Key('ganttRow-${tasksData.first.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('taskTitleField')), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
  });

  testWidgets('Гант помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final lanes = await loadLanes();
    final tasksData = await seedTasks();

    await tester.pumpWidget(app(lanes: lanes, tasksData: tasksData));
    await tester.pumpAndSettle();

    expect(find.text('Просроченная задача'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
