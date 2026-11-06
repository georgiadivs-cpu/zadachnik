import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/core/database/default_lanes.dart';
import 'package:zadachnik_client/features/tasks/data/lanes_repository.dart';
import 'package:zadachnik_client/features/tasks/data/tasks_repository.dart';
import 'package:zadachnik_client/features/tasks/domain/lane.dart';
import 'package:zadachnik_client/features/tasks/domain/task.dart';

void main() {
  late AppDatabase database;
  late LanesRepository lanes;
  late TasksRepository tasks;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    lanes = LanesRepository(database);
    tasks = TasksRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<Lane>> activeLanes() => lanes.watchAll().first;

  TaskDraft draft(String laneId, {String title = 'Задача'}) => TaskDraft(
    title: title,
    description: 'Описание',
    laneId: laneId,
    categoryId: 'work',
    priority: 'HIGH',
    plannedStartAt: DateTime.utc(2026, 11, 6, 9),
    plannedEndAt: DateTime.utc(2026, 11, 8, 18),
    actualStartAt: null,
    actualEndAt: null,
  );

  test('создаёт четыре дорожки по умолчанию', () async {
    final lanesData = await activeLanes();

    expect(lanesData, hasLength(4));
    expect(lanesData.map((lane) => lane.id), [
      DefaultLanes.newLaneId,
      DefaultLanes.inProgressLaneId,
      DefaultLanes.reviewLaneId,
      DefaultLanes.doneLaneId,
    ]);
    expect(lanesData.every((lane) => lane.syncStatus == 'SYNCED'), isTrue);
  });

  test('создаёт задачу локально, в outbox и истории', () async {
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final task = await tasks.findById(id);

    expect(task?.title, 'Задача');
    expect(task?.categoryName, 'Работа');
    expect(task?.priority, 'HIGH');
    expect(task?.syncStatus, 'PENDING');

    final operations = await database.select(database.syncOutbox).get();
    expect(operations, hasLength(1));
    expect(operations.single.entityType, 'TASK');
    expect(operations.single.operationType, 'CREATE');

    final history = await tasks.watchHistory(id).first;
    expect(history, hasLength(1));
    expect(history.single.fromLaneId, isNull);
    expect(history.single.toLaneId, DefaultLanes.newLaneId);
  });

  test('перемещение после sync создаёт UPDATE и запись истории', () async {
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final create = (await database.select(database.syncOutbox).get()).single;
    await tasks.applyPushSuccess(
      operationId: create.operationId,
      taskId: id,
      revision: 1,
      sentPayload: create.payload,
    );
    final task = (await tasks.findById(id))!;

    await tasks.moveToLane(task, DefaultLanes.inProgressLaneId);

    final operations = await database.select(database.syncOutbox).get();
    expect(operations, hasLength(1));
    expect(operations.single.operationType, 'UPDATE');
    expect(operations.single.baseRevision, 1);
    final payload =
        jsonDecode(operations.single.payload) as Map<String, dynamic>;
    expect(payload['laneId'], DefaultLanes.inProgressLaneId);
    expect(payload['systemState'], 'ACTIVE');

    final history = await tasks.watchHistory(id).first;
    expect(history, hasLength(2));
    expect(history.first.fromLaneId, DefaultLanes.newLaneId);
    expect(history.first.toLaneId, DefaultLanes.inProgressLaneId);
  });

  test('отмена и возврат сохраняют системное состояние в payload', () async {
    final id = await tasks.create(draft(DefaultLanes.newLaneId));
    final create = (await database.select(database.syncOutbox).get()).single;
    await tasks.applyPushSuccess(
      operationId: create.operationId,
      taskId: id,
      revision: 1,
      sentPayload: create.payload,
    );
    final task = (await tasks.findById(id))!;

    await tasks.setCancelled(task, true);
    var saved = (await tasks.findById(id))!;
    expect(saved.isCancelled, isTrue);
    var payload = jsonDecode(
      (await database.select(database.syncOutbox).get()).single.payload,
    ) as Map<String, dynamic>;
    expect(payload['systemState'], 'CANCELLED');

    await tasks.setCancelled(saved, false);
    saved = (await tasks.findById(id))!;
    expect(saved.isCancelled, isFalse);
    payload = jsonDecode(
      (await database.select(database.syncOutbox).get()).single.payload,
    ) as Map<String, dynamic>;
    expect(payload['systemState'], 'ACTIVE');
  });

  test('настройка дорожек переименовывает, добавляет и удаляет', () async {
    final initial = await activeLanes();
    await lanes.saveConfiguration([
      LaneDraft(id: initial[1].id, name: 'В работе'),
      LaneDraft(id: initial[0].id, name: 'Входящие'),
      LaneDraft(id: initial[2].id, name: 'Проверка'),
      LaneDraft(id: initial[3].id, name: 'Готово'),
      const LaneDraft(name: 'Идеи'),
    ]);

    var configured = await activeLanes();
    expect(configured, hasLength(5));
    expect(configured[0].id, initial[1].id);
    expect(configured[1].name, 'Входящие');
    expect(configured[4].name, 'Идеи');
    expect(configured[4].syncStatus, 'PENDING');

    final operations = await database.select(database.syncOutbox).get();
    expect(operations.where((op) => op.entityType == 'LANE'), hasLength(3));

    final newLane = configured[4];
    final create = operations.firstWhere(
      (op) => op.entityId == newLane.id && op.operationType == 'CREATE',
    );
    await lanes.applyPushSuccess(
      operationId: create.operationId,
      laneId: newLane.id,
      revision: 1,
      sentPayload: create.payload,
    );

    await lanes.saveConfiguration([
      LaneDraft(id: configured[0].id, name: 'В работе'),
      LaneDraft(id: configured[1].id, name: 'Входящие'),
      LaneDraft(id: configured[2].id, name: 'Проверка'),
      LaneDraft(id: configured[3].id, name: 'Готово'),
    ]);

    configured = await activeLanes();
    expect(configured, hasLength(4));
    final delete = (await database.select(database.syncOutbox).get())
        .firstWhere((op) => op.entityId == newLane.id);
    expect(delete.operationType, 'DELETE');
    expect(delete.baseRevision, 1);
  });

  test('нельзя удалить дорожку с задачами и оставить меньше трёх', () async {
    final initial = await activeLanes();
    await tasks.create(draft(DefaultLanes.newLaneId));

    await expectLater(
      lanes.saveConfiguration([
        LaneDraft(id: initial[1].id, name: initial[1].name),
        LaneDraft(id: initial[2].id, name: initial[2].name),
        LaneDraft(id: initial[3].id, name: initial[3].name),
      ]),
      throwsArgumentError,
    );

    await expectLater(
      lanes.saveConfiguration([
        LaneDraft(id: initial[0].id, name: initial[0].name),
        LaneDraft(id: initial[1].id, name: initial[1].name),
      ]),
      throwsArgumentError,
    );
  });
}
