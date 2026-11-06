import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../data/backup_api.dart';
import '../data/backup_status_store.dart';
import '../data/device_snapshot_service.dart';
import '../domain/backup_models.dart';

final backupApiProvider = Provider<BackupApi>((ref) => DioBackupApi());

final backupStatusStoreProvider = Provider<BackupStatusStore>(
  (ref) => BackupStatusStore(),
);

final deviceSnapshotServiceProvider = Provider<DeviceSnapshotService>((ref) {
  return DeviceSnapshotService(ref.watch(appDatabaseProvider));
});

final backupControllerProvider =
    NotifierProvider<BackupController, BackupViewState>(BackupController.new);

class BackupViewState {
  const BackupViewState({
    this.status,
    this.loading = false,
    this.busy = false,
    this.offline = false,
    this.initialized = false,
    this.error,
  });

  final BackupStatusSnapshot? status;
  final bool loading;
  final bool busy;
  final bool offline;
  final bool initialized;
  final String? error;

  BackupViewState copyWith({
    BackupStatusSnapshot? status,
    bool? loading,
    bool? busy,
    bool? offline,
    bool? initialized,
    String? error,
    bool clearError = false,
  }) {
    return BackupViewState(
      status: status ?? this.status,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      offline: offline ?? this.offline,
      initialized: initialized ?? this.initialized,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BackupController extends Notifier<BackupViewState> {
  bool _initialized = false;

  @override
  BackupViewState build() => const BackupViewState();

  Future<void> initialize() async {
    if (_initialized) {
      await refresh(showLoading: true);
      return;
    }
    _initialized = true;
    final cached = await ref.read(backupStatusStoreProvider).read();
    if (cached != null) {
      state = state.copyWith(status: cached, initialized: true);
    }
    await refresh(showLoading: true);
    state = state.copyWith(initialized: true);
  }

  Future<void> refresh({bool showLoading = false, bool silent = false}) async {
    if (showLoading) {
      state = state.copyWith(loading: true);
    }
    final session = await ref
        .read(authControllerProvider.notifier)
        .ensureFreshSession();
    if (session == null) {
      state = state.copyWith(
        loading: false,
        error: 'Требуется вход в аккаунт',
        offline: true,
      );
      return;
    }
    try {
      final status = await ref
          .read(backupApiProvider)
          .status(accessToken: session.accessToken);
      state = state.copyWith(
        status: status,
        loading: false,
        offline: false,
        error: null,
        clearError: true,
      );
      await ref.read(backupStatusStoreProvider).write(status);
    } on BackupFailure catch (failure) {
      if (failure.unauthorized) {
        final fresh = await ref
            .read(authControllerProvider.notifier)
            .ensureFreshSession(force: true);
        if (fresh != null && fresh.accessToken != session.accessToken) {
          try {
            final status = await ref
                .read(backupApiProvider)
                .status(accessToken: fresh.accessToken);
            state = state.copyWith(
              status: status,
              loading: false,
              offline: false,
              error: null,
              clearError: true,
            );
            await ref.read(backupStatusStoreProvider).write(status);
            return;
          } on BackupFailure catch (retryFailure) {
            state = state.copyWith(
              loading: false,
              error: retryFailure.message,
              offline: retryFailure.network,
            );
            return;
          }
        }
      }
      state = state.copyWith(
        loading: false,
        offline: failure.network,
        error: silent && failure.network ? null : failure.message,
      );
    }
  }

  Future<String?> startBackup() async {
    if (state.busy) {
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .ensureFreshSession();
      if (session == null) {
        return 'Требуется вход в аккаунт';
      }
      final status = await ref
          .read(backupApiProvider)
          .start(accessToken: session.accessToken);
      state = state.copyWith(status: status, offline: false, clearError: true);
      await ref.read(backupStatusStoreProvider).write(status);
      return null;
    } on BackupFailure catch (failure) {
      state = state.copyWith(error: failure.message, offline: failure.network);
      return failure.message;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<String?> verifyArchive(String archiveId) async {
    if (state.busy) {
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .ensureFreshSession();
      if (session == null) {
        return 'Требуется вход в аккаунт';
      }
      await ref
          .read(backupApiProvider)
          .verify(accessToken: session.accessToken, archiveId: archiveId);
      await refresh(silent: true);
      return null;
    } on BackupFailure catch (failure) {
      state = state.copyWith(error: failure.message);
      return failure.message;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<String?> uploadDeviceSnapshot() async {
    if (state.busy) {
      return null;
    }
    state = state.copyWith(busy: true, clearError: true);
    PreparedSnapshot? prepared;
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .ensureFreshSession();
      if (session == null) {
        return 'Требуется вход в аккаунт';
      }
      prepared = await ref.read(deviceSnapshotServiceProvider).prepare();
      await ref
          .read(backupApiProvider)
          .uploadDeviceSnapshot(
            accessToken: session.accessToken,
            localPath: prepared.path,
            sha256: prepared.sha256,
            schemaVersion: prepared.schemaVersion,
          );
      await refresh(silent: true);
      return null;
    } on SnapshotExportFailure catch (failure) {
      state = state.copyWith(error: failure.message);
      return failure.message;
    } on BackupFailure catch (failure) {
      state = state.copyWith(error: failure.message, offline: failure.network);
      return failure.message;
    } finally {
      if (prepared != null) {
        await ref.read(deviceSnapshotServiceProvider).discard(prepared);
      }
      state = state.copyWith(busy: false);
    }
  }
}
