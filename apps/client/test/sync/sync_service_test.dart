import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadachnik_client/core/auth/session.dart';
import 'package:zadachnik_client/core/database/app_database.dart';
import 'package:zadachnik_client/features/notes/data/notes_repository.dart';
import 'package:zadachnik_client/features/sync/application/sync_service.dart';
import 'package:zadachnik_client/features/sync/data/sync_api.dart';
import 'package:zadachnik_client/features/sync/data/sync_repository.dart';

void main() {
  late AppDatabase database;
  late NotesRepository notes;
  late SyncRepository syncRepository;
  late FakeSyncApi api;
  late Session session;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    notes = NotesRepository(database);
    syncRepository = SyncRepository(database);
    api = FakeSyncApi();
    session = Session(
      email: 'owner@example.com',
      userId: 'user-1',
      deviceId: 'device-1',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      accessExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  SyncService service({SessionResolver? resolver}) => SyncService(
    database: database,
    notes: notes,
    syncRepository: syncRepository,
    api: api,
    sessionResolver: resolver ?? ({bool force = false}) async => session,
  );

  test('APPLIED удаляет операцию из outbox и сохраняет revision', () async {
    final id = await notes.create(
      title: 'Заметка',
      contentMarkdown: '# Текст',
      categoryId: 'personal',
    );
    api.pushHandler = (operations) async => [
      PushOutcome(
        operationId: operations.single.operationId,
        status: 'APPLIED',
        entityId: id,
        revision: 2,
      ),
    ];

    final summary = await service().sync();

    expect(summary.pushed, 1);
    expect(summary.pulled, 0);
    expect(summary.conflicts, 0);
    expect(summary.rejected, 0);
    expect(await pendingOperations(database), isEmpty);

    final note = await notes.findById(id);
    expect(note?.revision, 2);
    expect(note?.syncStatus, 'SYNCED');
    expect(await syncRepository.readCursor(session.userId), '0');
  });

  test(
    'DUPLICATE считается успехом и не оставляет операцию в outbox',
    () async {
      final id = await notes.create(
        title: 'Заметка',
        contentMarkdown: 'Текст',
        categoryId: 'work',
      );
      api.pushHandler = (operations) async => [
        PushOutcome(
          operationId: operations.single.operationId,
          status: 'DUPLICATE',
          entityId: id,
          revision: 4,
        ),
      ];

      final summary = await service().sync();

      expect(summary.pushed, 1);
      expect(await pendingOperations(database), isEmpty);
      expect((await notes.findById(id))?.revision, 4);
    },
  );

  test('CONFLICT сохраняет серверную версию и обе версии данных', () async {
    final id = await notes.create(
      title: 'Локальная',
      contentMarkdown: 'Локальный текст',
      categoryId: 'work',
    );
    final serverPayload = _payload(
      id: id,
      title: 'Серверная',
      contentMarkdown: 'Серверный текст',
      revision: 3,
    );
    api.pushHandler = (operations) async => [
      PushOutcome(
        operationId: operations.single.operationId,
        status: 'CONFLICT',
        entityId: id,
        revision: 3,
        serverEntity: serverPayload,
      ),
    ];

    final summary = await service().sync();

    expect(summary.conflicts, 1);
    expect(summary.pushed, 0);
    expect(await pendingOperations(database), isEmpty);

    final local = await notes.findById(id);
    expect(local?.title, 'Локальная');
    expect(local?.syncStatus, 'CONFLICT');

    final conflicts = await database.select(database.conflicts).get();
    expect(conflicts, hasLength(1));
    expect(conflicts.single.entityId, id);
    expect(conflicts.single.serverVersion, 3);
    final saved =
        jsonDecode(conflicts.single.serverPayload) as Map<String, dynamic>;
    expect(saved['title'], 'Серверная');
  });

  test(
    'REJECTED помечает операцию ошибкой и не теряет локальные данные',
    () async {
      final id = await notes.create(
        title: 'Заметка',
        contentMarkdown: 'Текст',
        categoryId: 'family',
      );
      api.pushHandler = (operations) async => [
        PushOutcome(
          operationId: operations.single.operationId,
          status: 'REJECTED',
          code: 'VALIDATION_ERROR',
          message: 'Некорректные данные',
        ),
      ];

      final summary = await service().sync();

      expect(summary.rejected, 1);
      expect(summary.pushed, 0);

      final pending = await pendingOperations(database);
      expect(pending, hasLength(1));
      expect(pending.single.attempts, 1);
      expect(pending.single.lastError, 'Некорректные данные');

      final note = await notes.findById(id);
      expect(note?.syncStatus, 'ERROR');
      expect(note?.title, 'Заметка');
    },
  );

  test('pull применяет изменения и сохраняет nextCursor', () async {
    final id = 'note-remote-1';
    api.pullHandler = (cursor, limit) async => PullPage(
      changes: [
        _change(
          seq: 7,
          payload: _payload(
            id: id,
            title: 'С сервера',
            contentMarkdown: '# Удалённая',
            revision: 1,
            categoryId: 'work',
          ),
        ),
      ],
      nextCursor: '7',
      hasMore: false,
    );

    final summary = await service().sync();

    expect(summary.pulled, 1);
    expect(summary.conflicts, 0);
    expect(await syncRepository.readCursor(session.userId), '7');

    final note = await notes.findById(id);
    expect(note?.title, 'С сервера');
    expect(note?.contentMarkdown, '# Удалённая');
    expect(note?.categoryName, 'Работа');
    expect(note?.syncStatus, 'SYNCED');
  });

  test('pull читает все страницы, пока hasMore = true', () async {
    var call = 0;
    api.pullHandler = (cursor, limit) async {
      call += 1;
      if (call == 1) {
        expect(cursor, '0');
        return PullPage(
          changes: [
            _change(
              seq: 1,
              payload: _payload(id: 'note-a', title: 'A', revision: 1),
            ),
          ],
          nextCursor: '1',
          hasMore: true,
        );
      }

      expect(cursor, '1');
      return PullPage(
        changes: [
          _change(
            seq: 2,
            payload: _payload(id: 'note-b', title: 'B', revision: 1),
          ),
        ],
        nextCursor: '2',
        hasMore: false,
      );
    };

    final summary = await service().sync();

    expect(api.pullCalls, hasLength(2));
    expect(summary.pulled, 2);
    expect(await syncRepository.readCursor(session.userId), '2');
    expect((await notes.findById('note-a'))?.title, 'A');
    expect((await notes.findById('note-b'))?.title, 'B');
  });

  test('pull применяет tombstone и убирает заметку из списка', () async {
    const id = 'note-remote-delete';
    var call = 0;
    api.pullHandler = (cursor, limit) async {
      call += 1;
      if (call == 1) {
        return PullPage(
          changes: [
            _change(
              seq: 1,
              payload: _payload(id: id, title: 'Удаляемая', revision: 1),
            ),
          ],
          nextCursor: '1',
          hasMore: false,
        );
      }

      return PullPage(
        changes: [
          _change(
            seq: 2,
            payload: _payload(
              id: id,
              title: 'Удаляемая',
              revision: 2,
              deletedAt: DateTime.utc(2026, 11, 6, 13),
            ),
          ),
        ],
        nextCursor: '2',
        hasMore: false,
      );
    };

    await service().sync();
    expect(await notes.watchAll().first, hasLength(1));

    final summary = await service().sync();

    expect(summary.pulled, 1);
    expect(await notes.watchAll().first, isEmpty);
    expect(await syncRepository.readCursor(session.userId), '2');
    final rows = await database.select(database.notes).get();
    expect(rows.single.deletedAt, isNotNull);
  });

  test(
    'cursor не двигается, если применение страницы завершилось ошибкой',
    () async {
      await syncRepository.writeCursor(session.userId, '3');
      api.pullHandler = (cursor, limit) async => const PullPage(
        changes: [
          PullChange(
            seq: 4,
            entityType: 'NOTE',
            entityId: 'broken',
            operationType: 'UPDATE',
            revision: 2,
            payload: {},
          ),
        ],
        nextCursor: '4',
        hasMore: false,
      );

      await expectLater(service().sync(), throwsA(anything));

      expect(await syncRepository.readCursor(session.userId), '3');
      expect(await notes.findById('broken'), isNull);
    },
  );

  test('offline сохраняет outbox и возвращает признак недоступности', () async {
    final id = await notes.create(
      title: 'Локальная',
      contentMarkdown: 'Текст',
      categoryId: 'personal',
    );
    api.pushError = const SyncFailure(
      code: 'NETWORK_ERROR',
      message: 'Сервер недоступен',
      network: true,
    );

    final summary = await service().sync();

    expect(summary.offline, isTrue);
    expect(summary.pushed, 0);
    expect(summary.error, isNull);
    expect(await pendingOperations(database), hasLength(1));
    expect((await notes.findById(id))?.syncStatus, 'PENDING');
    expect(api.pullCalls, isEmpty);
  });

  test('локальная правка во время push не теряется', () async {
    final id = await notes.create(
      title: 'Старая',
      contentMarkdown: 'Старый текст',
      categoryId: 'personal',
    );
    final created = (await notes.findById(id))!;
    var pushCount = 0;
    api.pushHandler = (operations) async {
      pushCount += 1;
      if (pushCount == 1) {
        await notes.updateLocal(
          note: created,
          title: 'Новая',
          contentMarkdown: 'Новый текст',
          categoryId: 'work',
        );
        return [
          PushOutcome(
            operationId: operations.single.operationId,
            status: 'APPLIED',
            entityId: id,
            revision: 2,
          ),
        ];
      }
      throw const SyncFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер недоступен',
        network: true,
      );
    };

    final first = await service().sync();

    expect(first.offline, isTrue);
    final pending = await pendingOperations(database);
    expect(pending, hasLength(1));
    expect(pending.single.operationType, 'UPDATE');
    expect(pending.single.baseRevision, 2);
    expect(
      (jsonDecode(pending.single.payload) as Map<String, dynamic>)['title'],
      'Новая',
    );
    final afterFirst = await notes.findById(id);
    expect(afterFirst?.title, 'Новая');
    expect(afterFirst?.revision, 2);
    expect(afterFirst?.syncStatus, 'PENDING');

    api.pushHandler = (operations) async => [
      PushOutcome(
        operationId: operations.single.operationId,
        status: 'APPLIED',
        entityId: id,
        revision: 3,
      ),
    ];
    final second = await service().sync();

    expect(second.pushed, 1);
    expect(api.pushCalls[1].single.baseRevision, 2);
    expect(await pendingOperations(database), isEmpty);
    expect((await notes.findById(id))?.syncStatus, 'SYNCED');
    expect((await notes.findById(id))?.revision, 3);
  });

  test(
    'offline → online: outbox отправляется после восстановления сети',
    () async {
      final id = await notes.create(
        title: 'Локальная',
        contentMarkdown: 'Текст',
        categoryId: 'personal',
      );
      api.pushError = const SyncFailure(
        code: 'NETWORK_ERROR',
        message: 'Сервер недоступен',
        network: true,
      );

      final offline = await service().sync();
      expect(offline.offline, isTrue);
      expect(await pendingOperations(database), hasLength(1));

      api.pushError = null;
      api.pushHandler = (operations) async => [
        PushOutcome(
          operationId: operations.single.operationId,
          status: 'APPLIED',
          entityId: id,
          revision: 2,
        ),
      ];

      final online = await service().sync();

      expect(online.offline, isFalse);
      expect(online.pushed, 1);
      expect(await pendingOperations(database), isEmpty);
      expect((await notes.findById(id))?.revision, 2);
      expect((await notes.findById(id))?.syncStatus, 'SYNCED');
    },
  );

  test('при 401 обновляет сессию и повторяет цикл один раз', () async {
    final id = await notes.create(
      title: 'Заметка',
      contentMarkdown: 'Текст',
      categoryId: 'work',
    );
    final refreshed = Session(
      email: session.email,
      userId: session.userId,
      deviceId: session.deviceId,
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
      accessExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    final forces = <bool>[];
    var pushCall = 0;
    api.pushHandler = (operations) async {
      pushCall += 1;
      if (pushCall == 1) {
        throw const SyncFailure(
          code: 'UNAUTHORIZED',
          message: 'Сессия истекла',
          unauthorized: true,
        );
      }
      expect(operations.single.deviceId, session.deviceId);
      return [
        PushOutcome(
          operationId: operations.single.operationId,
          status: 'APPLIED',
          entityId: id,
          revision: 2,
        ),
      ];
    };

    final summary = await service(
      resolver: ({bool force = false}) async {
        forces.add(force);
        return force ? refreshed : session;
      },
    ).sync();

    expect(forces, [false, true]);
    expect(api.pushCalls, hasLength(2));
    expect(api.lastAccessToken, 'access-2');
    expect(summary.pushed, 1);
    expect(await pendingOperations(database), isEmpty);
  });
}

Future<List<SyncOutboxData>> pendingOperations(AppDatabase database) =>
    database.select(database.syncOutbox).get();

Map<String, dynamic> _payload({
  required String id,
  required String title,
  String contentMarkdown = '',
  String? categoryId,
  int revision = 1,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 11, 6, 12);
  return {
    'id': id,
    'title': title,
    'contentMarkdown': contentMarkdown,
    'categoryId': categoryId,
    'revision': revision,
    'createdAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };
}

PullChange _change({required int seq, required Map<String, dynamic> payload}) =>
    PullChange(
      seq: seq,
      entityType: 'NOTE',
      entityId: payload['id'] as String,
      operationType: 'CREATE',
      revision: payload['revision'] as int,
      payload: payload,
    );

class FakeSyncApi implements SyncApi {
  Future<List<PushOutcome>> Function(List<SyncOperationRequest> operations)?
  pushHandler;
  Future<PullPage> Function(String cursor, int limit)? pullHandler;
  Object? pushError;
  Object? pullError;

  final List<List<SyncOperationRequest>> pushCalls = [];
  final List<String> pullCalls = [];
  String? lastAccessToken;

  @override
  Future<List<PushOutcome>> push({
    required String accessToken,
    required List<SyncOperationRequest> operations,
  }) async {
    pushCalls.add(operations);
    lastAccessToken = accessToken;
    if (pushError != null) {
      throw pushError!;
    }
    return pushHandler?.call(operations) ?? const [];
  }

  @override
  Future<PullPage> pull({
    required String accessToken,
    required String cursor,
    int limit = 200,
  }) async {
    pullCalls.add(cursor);
    lastAccessToken = accessToken;
    if (pullError != null) {
      throw pullError!;
    }
    return pullHandler?.call(cursor, limit) ??
        PullPage(changes: const [], nextCursor: cursor, hasMore: false);
  }
}
