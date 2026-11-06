class BackupArchiveView {
  const BackupArchiveView({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.finishedAt,
    required this.sizeBytes,
    required this.sha256,
    required this.status,
    required this.verifiedAt,
    required this.schemaVersion,
    required this.counts,
    required this.error,
  });

  final String id;
  final String fileName;
  final DateTime createdAt;
  final DateTime finishedAt;
  final int sizeBytes;
  final String sha256;
  final String status;
  final DateTime? verifiedAt;
  final String? schemaVersion;
  final Map<String, int> counts;
  final String? error;

  bool get verified => status == 'VERIFIED' && verifiedAt != null;

  factory BackupArchiveView.fromJson(Map<String, dynamic> json) {
    return BackupArchiveView(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      finishedAt: DateTime.parse(json['finishedAt'] as String).toLocal(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      status: json['status'] as String? ?? 'SUCCESS',
      verifiedAt: _date(json['verifiedAt']),
      schemaVersion: json['schemaVersion'] as String?,
      counts: _counts(json['counts']),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'status': status,
    'verifiedAt': verifiedAt?.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'counts': counts,
    'error': error,
  };
}

class BackupDeviceView {
  const BackupDeviceView({
    required this.deviceId,
    required this.snapshotCount,
    required this.latest,
  });

  final String deviceId;
  final int snapshotCount;
  final BackupSnapshotView latest;

  factory BackupDeviceView.fromJson(Map<String, dynamic> json) {
    return BackupDeviceView(
      deviceId: json['deviceId'] as String,
      snapshotCount: (json['snapshotCount'] as num?)?.toInt() ?? 0,
      latest: BackupSnapshotView.fromJson(
        (json['latest'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'snapshotCount': snapshotCount,
    'latest': latest.toJson(),
  };
}

class BackupSnapshotView {
  const BackupSnapshotView({
    required this.id,
    required this.createdAt,
    required this.sizeBytes,
    required this.sha256,
    required this.schemaVersion,
  });

  final String id;
  final DateTime createdAt;
  final int sizeBytes;
  final String sha256;
  final int schemaVersion;

  factory BackupSnapshotView.fromJson(Map<String, dynamic> json) {
    return BackupSnapshotView(
      id: json['id'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'schemaVersion': schemaVersion,
  };
}

class BackupStatusSnapshot {
  const BackupStatusSnapshot({
    required this.configured,
    required this.configError,
    required this.running,
    required this.operation,
    required this.startedAt,
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.lastVerifiedAt,
    required this.lastError,
    required this.archives,
    required this.devices,
    required this.diskFreeBytes,
    required this.diskTotalBytes,
    required this.retentionRecent,
    required this.retentionWeekly,
    required this.retentionMonthly,
    required this.retentionDeviceSnapshots,
    required this.fetchedAt,
  });

  final bool configured;
  final String? configError;
  final bool running;
  final String? operation;
  final DateTime? startedAt;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastVerifiedAt;
  final String? lastError;
  final List<BackupArchiveView> archives;
  final List<BackupDeviceView> devices;
  final int diskFreeBytes;
  final int diskTotalBytes;
  final int retentionRecent;
  final int retentionWeekly;
  final int retentionMonthly;
  final int retentionDeviceSnapshots;
  final DateTime fetchedAt;

  BackupArchiveView? get latestArchive =>
      archives.isEmpty ? null : archives.first;

  bool get hasProblem =>
      !configured || lastError != null || latestArchive?.verified != true;

  factory BackupStatusSnapshot.fromJson(
    Map<String, dynamic> json, {
    DateTime? fetchedAt,
  }) {
    final state = (json['state'] as Map?)?.cast<String, dynamic>() ?? const {};
    final retention =
        (json['retention'] as Map?)?.cast<String, dynamic>() ?? const {};
    final disk = (json['disk'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BackupStatusSnapshot(
      configured: json['configured'] as bool? ?? false,
      configError: json['configError'] as String?,
      running: state['running'] as bool? ?? false,
      operation: state['operation'] as String?,
      startedAt: _date(state['startedAt']),
      lastAttemptAt: _date(state['lastAttemptAt']),
      lastSuccessAt: _date(state['lastSuccessAt']),
      lastVerifiedAt: _date(state['lastVerifiedAt']),
      lastError: state['lastError'] as String?,
      archives: ((json['archives'] as List?) ?? const [])
          .map(
            (item) => BackupArchiveView.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      devices: ((json['devices'] as List?) ?? const [])
          .map(
            (item) => BackupDeviceView.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      diskFreeBytes: (disk['freeBytes'] as num?)?.toInt() ?? 0,
      diskTotalBytes: (disk['totalBytes'] as num?)?.toInt() ?? 0,
      retentionRecent: (retention['recent'] as num?)?.toInt() ?? 7,
      retentionWeekly: (retention['weekly'] as num?)?.toInt() ?? 4,
      retentionMonthly: (retention['monthly'] as num?)?.toInt() ?? 6,
      retentionDeviceSnapshots:
          (retention['deviceSnapshots'] as num?)?.toInt() ?? 3,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'configured': configured,
    'configError': configError,
    'state': {
      'running': running,
      'operation': operation,
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'lastAttemptAt': lastAttemptAt?.toUtc().toIso8601String(),
      'lastSuccessAt': lastSuccessAt?.toUtc().toIso8601String(),
      'lastVerifiedAt': lastVerifiedAt?.toUtc().toIso8601String(),
      'lastError': lastError,
    },
    'archives': archives.map((archive) => archive.toJson()).toList(),
    'devices': devices.map((device) => device.toJson()).toList(),
    'disk': {'freeBytes': diskFreeBytes, 'totalBytes': diskTotalBytes},
    'retention': {
      'recent': retentionRecent,
      'weekly': retentionWeekly,
      'monthly': retentionMonthly,
      'deviceSnapshots': retentionDeviceSnapshots,
    },
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

Map<String, int> _counts(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map(
    (key, item) => MapEntry(key.toString(), item is num ? item.toInt() : 0),
  );
}
