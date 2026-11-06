import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/calendar/application/reminder_coordinator.dart';
import 'package:zadachnik_client/features/calendar/data/reminders_repository.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

import 'fakes.dart';

void main() {
  late AppDatabase database;
  late TasksRepository tasks;
  late RemindersRepository reminders;
  late FakeReminderScheduler scheduler;
  late ReminderCoordinator coordinator;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
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

  TaskDraft draft({String title = 'Задача'}) => TaskDraft(
    title: title,
    description: '',
    laneId: DefaultLanes.newLaneId,
    categoryId: 'work',
    priority: 'NORMAL',
    plannedStartAt: DateTime.utc(2030, 1, 10),
    plannedEndAt: DateTime.utc(2030, 1, 10),
    actualStartAt: null,
    actualEndAt: null,
  );

  test('сохраняет одно напоминание и планирует уведомление', () async {
    final taskId = await tasks.create(draft());
    final remindAt = DateTime.utc(2030, 1, 10, 14);

    final result = await coordinator.saveForTask(taskId, remindAt);

    expect(result.notificationsAllowed, isTrue);
    expect(result.reminder?.taskId, taskId);
    expect(result.reminder?.remindAt, remindAt);
    expect(scheduler.permissionCalls, 1);
    expect(scheduler.scheduled, hasLength(1));
    expect(await reminders.findForTask(taskId), isNotNull);

    final operations = await (database.select(
      database.syncOutbox,
    )..where((table) => table.entityType.equals('REMINDER'))).get();
    expect(operations, hasLength(1));
    expect(operations.single.operationType, 'CREATE');
  });

  test('обновляет напоминание и не создаёт второе', () async {
    final taskId = await tasks.create(draft());
    final first = await coordinator.saveForTask(
      taskId,
      DateTime.utc(2030, 1, 10, 14),
    );
    final create = (await (database.select(
      database.syncOutbox,
    )..where((table) => table.entityType.equals('REMINDER'))).get()).single;
    await reminders.applyPushSuccess(
      operationId: create.operationId,
      reminderId: first.reminder!.id,
      revision: 1,
      sentPayload: create.payload,
    );

    final second = await coordinator.saveForTask(
      taskId,
      DateTime.utc(2030, 1, 10, 16),
    );

    expect(second.reminder?.id, first.reminder?.id);
    final active = await reminders.listAllActive();
    expect(active, hasLength(1));
    expect(active.single.remindAt, DateTime.utc(2030, 1, 10, 16));

    final operations = await (database.select(
      database.syncOutbox,
    )..where((table) => table.entityType.equals('REMINDER'))).get();
    expect(operations, hasLength(1));
    expect(operations.single.operationType, 'UPDATE');
    expect(operations.single.baseRevision, 1);
    final payload =
        jsonDecode(operations.single.payload) as Map<String, dynamic>;
    expect(payload['remindAt'], '2030-01-10T16:00:00.000Z');
  });

  test('удаляет напоминание и снимает уведомление', () async {
    final taskId = await tasks.create(draft());
    final saved = await coordinator.saveForTask(
      taskId,
      DateTime.utc(2030, 1, 10, 14),
    );
    final create = (await (database.select(
      database.syncOutbox,
    )..where((table) => table.entityType.equals('REMINDER'))).get()).single;
    await reminders.applyPushSuccess(
      operationId: create.operationId,
      reminderId: saved.reminder!.id,
      revision: 1,
      sentPayload: create.payload,
    );

    await coordinator.cancelForTask(taskId);

    expect(await reminders.findForTask(taskId), isNull);
    expect(scheduler.cancelled, contains(saved.reminder!.id));
    final operations = await (database.select(
      database.syncOutbox,
    )..where((table) => table.entityType.equals('REMINDER'))).get();
    expect(operations, hasLength(1));
    expect(operations.single.operationType, 'DELETE');
  });

  test(
    'без разрешения сохраняет напоминание, но не планирует уведомление',
    () async {
      scheduler.permission = false;
      final taskId = await tasks.create(draft());

      final result = await coordinator.saveForTask(
        taskId,
        DateTime.utc(2030, 1, 10, 14),
      );

      expect(result.reminder, isNotNull);
      expect(result.notificationsAllowed, isFalse);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, contains(result.reminder!.id));
      expect(await reminders.findForTask(taskId), isNotNull);
    },
  );

  test(
    'reconcile планирует будущие и снимает прошедшие или отменённые',
    () async {
      final futureId = await tasks.create(draft(title: 'Будущая'));
      final pastId = await tasks.create(draft(title: 'Прошедшая'));
      final cancelledId = await tasks.create(draft(title: 'Отменённая'));

      await coordinator.saveForTask(futureId, DateTime.utc(2030, 1, 10, 14));
      await coordinator.saveForTask(pastId, DateTime.utc(2020, 1, 10, 14));
      final cancelledReminder = await coordinator.saveForTask(
        cancelledId,
        DateTime.utc(2030, 1, 10, 15),
      );
      final cancelledTask = (await tasks.findById(cancelledId))!;
      await tasks.setCancelled(cancelledTask, true);

      scheduler.scheduled.clear();
      scheduler.cancelled.clear();
      await coordinator.reconcile();

      expect(
        scheduler.scheduled.map((item) => item.taskId),
        contains(futureId),
      );
      expect(
        scheduler.scheduled.map((item) => item.taskId),
        isNot(contains(pastId)),
      );
      expect(scheduler.cancelled, contains(cancelledReminder.reminder!.id));
    },
  );
}
