import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/attachment.dart';

/// Локальные метаданные вложений. Файлы и серверная передача — снаружи.
class AttachmentsRepository {
  AttachmentsRepository(this._database);

  final AppDatabase _database;

  Stream<List<Attachment>> watchForOwner(
    AttachmentOwnerType ownerType,
    String ownerId,
  ) {
    final query = _database.select(_database.attachments)
      ..where(
        (table) =>
            table.ownerType.equals(ownerType.wire) &
            table.ownerId.equals(ownerId) &
            table.deletedAt.isNull(),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return query.watch().map((rows) => rows.map(_domain).toList());
  }

  Future<Attachment?> findById(String id) async {
    final row = await (_database.select(
      _database.attachments,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _domain(row);
  }

  Future<List<Attachment>> listPendingUploads() async {
    final rows =
        await (_database.select(_database.attachments)..where(
              (table) =>
                  table.deletedAt.isNull() &
                  table.uploadStatus.isIn(const ['PENDING', 'ERROR']),
            ))
            .get();
    return rows.map(_domain).toList();
  }

  Future<List<Attachment>> listPendingDownloads() async {
    final rows =
        await (_database.select(_database.attachments)..where(
              (table) =>
                  table.deletedAt.isNull() &
                  table.localPath.isNull() &
                  table.uploadStatus.isIn(const ['REMOTE', 'ERROR']),
            ))
            .get();
    return rows.map(_domain).toList();
  }

  Future<List<Attachment>> listPendingDeletes() async {
    final rows =
        await (_database.select(_database.attachments)..where(
              (table) =>
                  table.deletedAt.isNotNull() &
                  table.uploadStatus.equals('DELETE_PENDING'),
            ))
            .get();
    return rows.map(_domain).toList();
  }

  Future<List<Attachment>> listRemoteDeletes() async {
    final rows =
        await (_database.select(_database.attachments)..where(
              (table) =>
                  table.deletedAt.isNotNull() &
                  table.uploadStatus.equals('DELETED'),
            ))
            .get();
    return rows.map(_domain).toList();
  }

  Future<Attachment> createLocal({
    required String id,
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    required String sha256,
    required String localPath,
  }) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType.wire,
            ownerId: ownerId,
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            sha256: sha256,
            localPath: Value(localPath),
            uploadStatus: const Value('PENDING'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await findById(id))!;
  }

  Future<void> markUploading(String id) => _setStatus(id, 'UPLOADING');

  Future<void> markReady({
    required String id,
    required int revision,
    required String sha256,
    required String mimeType,
    required int sizeBytes,
  }) async {
    await (_database.update(
      _database.attachments,
    )..where((table) => table.id.equals(id))).write(
      AttachmentsCompanion(
        serverRevision: Value(revision),
        sha256: Value(sha256),
        mimeType: Value(mimeType),
        sizeBytes: Value(sizeBytes),
        uploadStatus: const Value('READY'),
        errorMessage: const Value(null),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markDownloaded({
    required String id,
    required String localPath,
    required String sha256,
    required int sizeBytes,
  }) async {
    await (_database.update(
      _database.attachments,
    )..where((table) => table.id.equals(id))).write(
      AttachmentsCompanion(
        localPath: Value(localPath),
        sha256: Value(sha256),
        sizeBytes: Value(sizeBytes),
        uploadStatus: const Value('READY'),
        errorMessage: const Value(null),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markError(String id, String message) async {
    await (_database.update(
      _database.attachments,
    )..where((table) => table.id.equals(id))).write(
      AttachmentsCompanion(
        uploadStatus: const Value('ERROR'),
        errorMessage: Value(message),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markDeletePending(Attachment attachment) async {
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.attachments,
    )..where((table) => table.id.equals(attachment.id))).write(
      AttachmentsCompanion(
        uploadStatus: const Value('DELETE_PENDING'),
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteHard(String id) async {
    await (_database.delete(
      _database.attachments,
    )..where((table) => table.id.equals(id))).go();
  }

  Future<void> applyRemote(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final existing = await (_database.select(
      _database.attachments,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final deletedAt = _date(payload['deletedAt']);
    final sha256 = payload['sha256'] as String? ?? '';
    final keepLocal =
        existing?.localPath != null &&
        existing?.sha256 == sha256 &&
        deletedAt == null;
    final status = deletedAt != null
        ? 'DELETED'
        : keepLocal
        ? 'READY'
        : 'REMOTE';
    final localPath = deletedAt != null
        ? existing?.localPath
        : keepLocal
        ? existing?.localPath
        : null;
    final companion = AttachmentsCompanion(
      id: Value(id),
      ownerType: Value(payload['ownerType'] as String? ?? 'NOTE'),
      ownerId: Value(payload['ownerId'] as String? ?? ''),
      fileName: Value(payload['fileName'] as String? ?? 'Файл'),
      mimeType: Value(
        payload['mimeType'] as String? ?? 'application/octet-stream',
      ),
      sizeBytes: Value((payload['sizeBytes'] as num?)?.toInt() ?? 0),
      sha256: Value(sha256),
      localPath: Value(localPath),
      serverRevision: Value((payload['revision'] as num?)?.toInt() ?? 1),
      uploadStatus: Value(status),
      errorMessage: const Value(null),
      createdAt: Value(
        _date(payload['createdAt']) ?? existing?.createdAt ?? now,
      ),
      updatedAt: Value(
        _date(payload['updatedAt']) ?? existing?.updatedAt ?? now,
      ),
      deletedAt: Value(deletedAt),
    );
    if (existing == null) {
      await _database.into(_database.attachments).insert(companion);
    } else {
      await (_database.update(
        _database.attachments,
      )..where((table) => table.id.equals(id))).write(companion);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    await (_database.update(
      _database.attachments,
    )..where((table) => table.id.equals(id))).write(
      AttachmentsCompanion(
        uploadStatus: Value(status),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  static Attachment _domain(AttachmentRow row) => Attachment(
    id: row.id,
    ownerType: AttachmentOwnerTypeWire.fromWire(row.ownerType),
    ownerId: row.ownerId,
    fileName: row.fileName,
    mimeType: row.mimeType,
    sizeBytes: row.sizeBytes,
    sha256: row.sha256,
    localPath: row.localPath,
    serverRevision: row.serverRevision,
    uploadStatus: row.uploadStatus,
    errorMessage: row.errorMessage,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );

  static DateTime? _date(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
