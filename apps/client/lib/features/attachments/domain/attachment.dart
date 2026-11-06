enum AttachmentOwnerType { note, task }

extension AttachmentOwnerTypeWire on AttachmentOwnerType {
  String get wire => switch (this) {
    AttachmentOwnerType.note => 'NOTE',
    AttachmentOwnerType.task => 'TASK',
  };

  static AttachmentOwnerType fromWire(String value) => switch (value) {
    'TASK' => AttachmentOwnerType.task,
    _ => AttachmentOwnerType.note,
  };
}

class Attachment {
  const Attachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.localPath,
    required this.serverRevision,
    required this.uploadStatus,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final AttachmentOwnerType ownerType;
  final String ownerId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final String? localPath;
  final int serverRevision;
  final String uploadStatus;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isUploaded => serverRevision > 0;
  bool get isDeleted => deletedAt != null;
  bool get isReady =>
      uploadStatus == 'READY' && localPath != null && !isDeleted;

  Attachment copyWith({
    String? localPath,
    int? serverRevision,
    String? uploadStatus,
    String? errorMessage,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Attachment(
    id: id,
    ownerType: ownerType,
    ownerId: ownerId,
    fileName: fileName,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    sha256: sha256,
    localPath: localPath ?? this.localPath,
    serverRevision: serverRevision ?? this.serverRevision,
    uploadStatus: uploadStatus ?? this.uploadStatus,
    errorMessage: errorMessage ?? this.errorMessage,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

class AttachmentRules {
  static const maxBytes = 25 * 1024 * 1024;
  static const extensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'pdf',
    'txt',
    'md',
    'markdown',
    'mp3',
    'm4a',
  ];

  static const _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heic',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'markdown': 'text/markdown',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
  };

  static String? mimeForName(String name) {
    final extension = name.split('.').last.toLowerCase();
    return _mimeByExtension[extension];
  }

  static bool isAllowedName(String name) => mimeForName(name) != null;

  static String formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes Б';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}
