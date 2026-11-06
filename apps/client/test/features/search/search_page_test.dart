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
import 'package:zadachnik_client/features/notes/application/notes_providers.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/search/data/search_repository.dart';
import 'package:zadachnik_client/features/search/presentation/search_page.dart';
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
  late NotesRepository notes;
  late TasksRepository tasks;
  late LanesRepository lanesRepository;
  late RemindersRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderCoordinator coordinator;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    notes = NotesRepository(database);
    tasks = TasksRepository(database);
    lanesRepository = LanesRepository(database);
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

  Future<void> seed() async {
    await notes.create(
      title: 'Планы на неделю',
      contentMarkdown: 'Собрать план и согласовать встречу.',
      categoryId: 'work',
    );
    await tasks.create(
      TaskDraft(
        title: 'Подготовить план',
        description: 'Собрать участников и вопросы.',
        laneId: DefaultLanes.inProgressLaneId,
        categoryId: 'work',
        priority: 'HIGH',
        plannedStartAt: null,
        plannedEndAt: null,
        actualStartAt: null,
        actualEndAt: null,
      ),
    );
  }

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

  Widget app({List<Lane> lanes = const []}) {
    return ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(
          DriftSearchRepository(database),
        ),
        notesRepositoryProvider.overrideWithValue(notes),
        tasksRepositoryProvider.overrideWithValue(tasks),
        lanesRepositoryProvider.overrideWithValue(lanesRepository),
        remindersRepositoryProvider.overrideWithValue(reminders),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderCoordinatorProvider.overrideWithValue(coordinator),
        lanesProvider.overrideWith((ref) => Stream.value(lanes)),
        syncControllerProvider.overrideWith(NoopSyncController.new),
      ],
      child: const MaterialApp(home: SearchPage()),
    );
  }

  testWidgets('ищет заметки и задачи и применяет фильтр типа', (tester) async {
    await seed();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Начните вводить запрос'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('searchField')), 'план');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.textContaining('Планы на неделю'), findsOneWidget);
    expect(find.textContaining('Подготовить план'), findsOneWidget);
    expect(find.text('Заметки · 1'), findsOneWidget);
    expect(find.text('Задачи · 1'), findsOneWidget);

    await tester.tap(find.text('Заметки'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Планы на неделю'), findsOneWidget);
    expect(find.textContaining('Подготовить план'), findsNothing);
  });

  testWidgets('показывает пустое состояние при отсутствии совпадений', (
    tester,
  ) async {
    await seed();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('searchField')),
      'совершенно другой запрос',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('открывает заметку из результатов', (tester) async {
    await seed();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchField')), 'план');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Планы на неделю'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noteTitleField')), findsOneWidget);
    expect(find.text('Планы на неделю'), findsWidgets);
  });

  testWidgets('открывает задачу из результатов', (tester) async {
    await seed();
    final lanes = await loadLanes();
    await tester.pumpWidget(app(lanes: lanes));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchField')), 'план');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Подготовить план'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('taskTitleField')), findsOneWidget);
  });

  testWidgets('поиск помещается на узком экране', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await seed();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchField')), 'план');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.textContaining('Планы на неделю'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
