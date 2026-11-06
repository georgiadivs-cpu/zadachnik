import 'package:zadachnik_client/features/backup/data/backup_api.dart';
import 'package:zadachnik_client/features/backup/domain/backup_models.dart';

class FakeBackupApi implements BackupApi {
  BackupStatusSnapshot? statusResponse;
  BackupArchiveView? verifyResponse;
  BackupSnapshotView? uploadResponse;
  BackupFailure? failure;
  int statusCalls = 0;
  int startCalls = 0;
  int verifyCalls = 0;
  int uploadCalls = 0;

  @override
  Future<BackupStatusSnapshot> status({required String accessToken}) async {
    statusCalls += 1;
    if (failure != null) throw failure!;
    return statusResponse ?? makeStatus();
  }

  @override
  Future<BackupStatusSnapshot> start({required String accessToken}) async {
    startCalls += 1;
    if (failure != null) throw failure!;
    return statusResponse ?? makeStatus(running: true);
  }

  @override
  Future<BackupArchiveView> verify({
    required String accessToken,
    required String archiveId,
  }) async {
    verifyCalls += 1;
    if (failure != null) throw failure!;
    return verifyResponse ?? makeStatus().archives.first;
  }

  @override
  Future<BackupSnapshotView> uploadDeviceSnapshot({
    required String accessToken,
    required String localPath,
    required String sha256,
    required int schemaVersion,
  }) async {
    uploadCalls += 1;
    if (failure != null) throw failure!;
    return uploadResponse ?? makeSnapshot();
  }
}

BackupStatusSnapshot makeStatus({
  bool configured = true,
  bool running = false,
  String? lastError,
  bool verified = true,
  List<BackupArchiveView>? archives,
  List<BackupDeviceView>? devices,
}) {
  final now = DateTime.now();
  final archive = BackupArchiveView(
    id: 'archive-1',
    fileName: 'zadachnik-20261106-081200-abcd.zip.age',
    createdAt: now.subtract(const Duration(hours: 1)),
    finishedAt: now.subtract(const Duration(minutes: 59)),
    sizeBytes: 2 * 1024 * 1024,
    sha256: List.filled(64, 'a').join(),
    status: verified ? 'VERIFIED' : 'SUCCESS',
    verifiedAt: verified ? now.subtract(const Duration(minutes: 58)) : null,
    schemaVersion: '7',
    counts: const {'notes': 4, 'tasks': 3, 'attachments': 2},
    error: null,
  );
  return BackupStatusSnapshot(
    configured: configured,
    configError: configured ? null : 'Не задан BACKUP_AGE_IDENTITY',
    running: running,
    operation: running ? 'BACKUP' : null,
    startedAt: running ? now : null,
    lastAttemptAt: now,
    lastSuccessAt: now.subtract(const Duration(hours: 1)),
    lastVerifiedAt: verified ? archive.verifiedAt : null,
    lastError: lastError,
    archives: archives ?? [archive],
    devices:
        devices ??
        [
          BackupDeviceView(
            deviceId: 'device-1',
            snapshotCount: 2,
            latest: makeSnapshot(),
          ),
        ],
    diskFreeBytes: 412 * 1024 * 1024 * 1024,
    diskTotalBytes: 2 * 1024 * 1024 * 1024 * 1024,
    retentionRecent: 7,
    retentionWeekly: 4,
    retentionMonthly: 6,
    retentionDeviceSnapshots: 3,
    fetchedAt: now,
  );
}

BackupSnapshotView makeSnapshot() => BackupSnapshotView(
  id: 'snapshot-1',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  sizeBytes: 3 * 1024 * 1024,
  sha256: List.filled(64, 'b').join(),
  schemaVersion: 6,
);
