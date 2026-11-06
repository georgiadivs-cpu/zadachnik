import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../../attachments/application/attachments_providers.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../tasks/application/tasks_providers.dart';
import '../data/sync_api.dart';
import '../data/sync_repository.dart';
import 'sync_service.dart';

enum SyncPhase { idle, running, success, error, offline }

class SyncViewState {
  const SyncViewState({
    required this.phase,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.message,
    this.lastSyncAt,
  });

  const SyncViewState.idle() : this(phase: SyncPhase.idle);

  final SyncPhase phase;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int rejected;
  final String? message;
  final DateTime? lastSyncAt;

  bool get isRunning => phase == SyncPhase.running;
}

final syncApiProvider = Provider<SyncApi>((ref) => DioSyncApi());

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository(ref.watch(appDatabaseProvider));
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    database: ref.watch(appDatabaseProvider),
    notes: ref.watch(notesRepositoryProvider),
    tasks: ref.watch(tasksRepositoryProvider),
    lanes: ref.watch(lanesRepositoryProvider),
    reminders: ref.watch(remindersRepositoryProvider),
    attachments: ref.watch(attachmentsRepositoryProvider),
    syncRepository: ref.watch(syncRepositoryProvider),
    api: ref.watch(syncApiProvider),
    sessionResolver: ({bool force = false}) => ref
        .read(authControllerProvider.notifier)
        .ensureFreshSession(force: force),
  );
});

final syncControllerProvider = NotifierProvider<SyncController, SyncViewState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncViewState> {
  bool _running = false;

  @override
  SyncViewState build() => const SyncViewState.idle();

  Future<void> sync() async {
    if (_running) {
      return;
    }
    _running = true;
    state = const SyncViewState(phase: SyncPhase.running);

    try {
      final summary = await ref.read(syncServiceProvider).sync();
      try {
        await ref.read(reminderCoordinatorProvider).reconcile();
      } on Object {
        // Ошибка уведомлений не должна менять результат синхронизации.
      }
      try {
        await ref.read(attachmentCoordinatorProvider).reconcile();
      } on Object {
        // Ошибка файлов не должна менять результат синхронизации.
      }
      if (!ref.mounted) {
        return;
      }
      final phase = summary.unauthorized
          ? SyncPhase.error
          : summary.offline
          ? SyncPhase.offline
          : summary.error != null
          ? SyncPhase.error
          : SyncPhase.success;
      state = SyncViewState(
        phase: phase,
        pushed: summary.pushed,
        pulled: summary.pulled,
        conflicts: summary.conflicts,
        rejected: summary.rejected,
        message: summary.unauthorized
            ? 'Требуется вход'
            : summary.error ?? (summary.offline ? 'Сервер недоступен' : null),
        lastSyncAt: phase == SyncPhase.success
            ? DateTime.now().toUtc()
            : state.lastSyncAt,
      );
    } on Object {
      if (ref.mounted) {
        state = const SyncViewState(
          phase: SyncPhase.error,
          message: 'Не удалось синхронизировать',
        );
      }
    } finally {
      _running = false;
    }
  }
}
