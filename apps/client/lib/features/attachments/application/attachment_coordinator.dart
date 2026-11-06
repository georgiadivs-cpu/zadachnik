import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/session.dart';
import '../data/attachment_api.dart';
import '../data/attachment_file_store.dart';
import '../data/attachments_repository.dart';
import '../domain/attachment.dart';

typedef AttachmentSessionResolver = Future<Session?> Function({bool force});

/// Добавляет файлы локально и синхронизирует их с сервером.
class AttachmentCoordinator {
  AttachmentCoordinator({
    required this.repository,
    required this.fileStore,
    required this.api,
    required this.sessionResolver,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AttachmentsRepository repository;
  final AttachmentFileStore fileStore;
  final AttachmentApi api;
  final AttachmentSessionResolver sessionResolver;
  final Uuid _uuid;
  bool _busy = false;

  Future<Attachment> addFile({
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required XFile file,
  }) async {
    final mimeType = AttachmentRules.mimeForName(file.name);
    if (mimeType == null) {
      throw ArgumentError('Тип файла не разрешён');
    }
    final length = await file.length();
    if (length == 0) {
      throw ArgumentError('Файл пуст');
    }
    if (length > AttachmentRules.maxBytes) {
      throw ArgumentError('Файл больше 25 МБ');
    }
    final id = _uuid.v4();
    final stored = await fileStore.store(id, file);
    if (stored.sizeBytes > AttachmentRules.maxBytes) {
      await fileStore.deletePath(stored.path);
      throw ArgumentError('Файл больше 25 МБ');
    }
    try {
      return await repository.createLocal(
        id: id,
        ownerType: ownerType,
        ownerId: ownerId,
        fileName: file.name,
        mimeType: mimeType,
        sizeBytes: stored.sizeBytes,
        sha256: stored.sha256,
        localPath: stored.path,
      );
    } on Object {
      await fileStore.deletePath(stored.path);
      rethrow;
    }
  }

  Future<void> deleteAttachment(Attachment attachment) async {
    if (attachment.serverRevision == 0) {
      if (attachment.localPath != null) {
        await fileStore.deletePath(attachment.localPath!);
      }
      await repository.deleteHard(attachment.id);
      return;
    }
    await repository.markDeletePending(attachment);
    if (attachment.localPath != null) {
      await fileStore.deletePath(attachment.localPath!);
    }
    await reconcile();
  }

  Future<void> retry(Attachment attachment) async {
    await reconcile();
  }

  Future<void> reconcile() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final session = await sessionResolver(force: false);
      if (session == null) {
        return;
      }
      await _cleanupRemoteDeletes();
      await _processDeletes(session);
      await _processDownloads(session);
      await _processUploads(session);
    } finally {
      _busy = false;
    }
  }

  Future<void> _cleanupRemoteDeletes() async {
    for (final attachment in await repository.listRemoteDeletes()) {
      if (attachment.localPath != null) {
        await fileStore.deletePath(attachment.localPath!);
      }
      await repository.deleteHard(attachment.id);
    }
  }

  Future<void> _processDeletes(Session session) async {
    for (final attachment in await repository.listPendingDeletes()) {
      try {
        await api.delete(
          accessToken: session.accessToken,
          attachmentId: attachment.id,
        );
        if (attachment.localPath != null) {
          await fileStore.deletePath(attachment.localPath!);
        }
        await repository.deleteHard(attachment.id);
      } on AttachmentApiFailure {
        // Оставляем DELETE_PENDING и повторим при следующем reconcile.
      } on Object {
        // Повторим при следующем reconcile.
      }
    }
  }

  Future<void> _processDownloads(Session session) async {
    for (final attachment in await repository.listPendingDownloads()) {
      try {
        final bytes = await api.download(
          accessToken: session.accessToken,
          attachmentId: attachment.id,
        );
        if (bytes.isEmpty) {
          await repository.markError(
            attachment.id,
            'Сервер вернул пустой файл',
          );
          continue;
        }
        final path = await fileStore.storeBytes(
          id: attachment.id,
          bytes: bytes,
          expectedSha256: attachment.sha256,
        );
        await repository.markDownloaded(
          id: attachment.id,
          localPath: path,
          sha256: attachment.sha256,
          sizeBytes: bytes.length,
        );
      } on AttachmentApiFailure catch (failure) {
        if (!failure.network && !failure.unauthorized) {
          await repository.markError(attachment.id, failure.message);
        }
      } on Object {
        await repository.markError(attachment.id, 'Не удалось сохранить файл');
      }
    }
  }

  Future<void> _processUploads(Session session) async {
    for (final attachment in await repository.listPendingUploads()) {
      final localPath = attachment.localPath;
      if (localPath == null || !await fileStore.exists(localPath)) {
        await repository.markError(attachment.id, 'Локальный файл не найден');
        continue;
      }
      await repository.markUploading(attachment.id);
      try {
        final remote = await api.upload(
          accessToken: session.accessToken,
          attachmentId: attachment.id,
          ownerType: attachment.ownerType,
          ownerId: attachment.ownerId,
          localPath: localPath,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
        );
        if (remote.sha256 != attachment.sha256) {
          await repository.markError(
            attachment.id,
            'Контрольная сумма не совпала',
          );
          continue;
        }
        await repository.markReady(
          id: attachment.id,
          revision: remote.revision,
          sha256: remote.sha256,
          mimeType: remote.mimeType,
          sizeBytes: remote.sizeBytes,
        );
      } on AttachmentApiFailure catch (failure) {
        await repository.markError(attachment.id, failure.message);
      } on Object {
        await repository.markError(attachment.id, 'Не удалось загрузить файл');
      }
    }
  }
}
