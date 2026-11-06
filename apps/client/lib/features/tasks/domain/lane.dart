/// Дорожка доски — рабочий статус задачи.
class Lane {
  const Lane({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.revision,
    required this.syncStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final int revision;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Черновик дорожки для сохранения настроек.
class LaneDraft {
  const LaneDraft({this.id, required this.name});

  final String? id;
  final String name;
}
