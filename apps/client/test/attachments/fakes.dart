import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:zadachnik_client/features/attachments/data/attachment_api.dart';
import 'package:zadachnik_client/features/attachments/data/attachment_file_store.dart';
import 'package:zadachnik_client/features/attachments/domain/attachment.dart';

class FakeAttachmentFileStore implements AttachmentFileStore {
  FakeAttachmentFileStore() {
    _directory = Directory.systemTemp.createTempSync('zadachnik-attachments-');
  }

  late final Directory _directory;
  final Map<String, List<int>> files = {};
  final List<String> deleted = [];
  int _counter = 0;

  @override
  Future<bool> exists(String path) async => File(path).exists();

  @override
  Future<StoredAttachmentFile> store(String id, XFile file) async {
    final bytes = await file.readAsBytes();
    final path = '${_directory.path}/$id';
    await File(path).writeAsBytes(bytes);
    files[path] = bytes;
    return StoredAttachmentFile(
      path: path,
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<String> storeBytes({
    required String id,
    required List<int> bytes,
    required String expectedSha256,
  }) async {
    final digest = sha256.convert(bytes).toString();
    if (digest != expectedSha256) {
      throw StateError('checksum mismatch');
    }
    final path = '${_directory.path}/$id-${_counter++}';
    await File(path).writeAsBytes(bytes);
    files[path] = List<int>.from(bytes);
    return path;
  }

  Future<void> dispose() async {
    if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  }

  @override
  Future<void> deletePath(String path) async {
    deleted.add(path);
    files.remove(path);
    final file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

class FakeAttachmentApi implements AttachmentApi {
  final Map<String, List<int>> remoteFiles = {};
  final List<String> uploads = [];
  final List<String> downloads = [];
  final List<String> deletes = [];
  AttachmentApiFailure? uploadFailure;
  AttachmentApiFailure? downloadFailure;
  AttachmentApiFailure? deleteFailure;
  String? forcedSha;
  int nextRevision = 1;

  @override
  Future<RemoteAttachment> upload({
    required String accessToken,
    required String attachmentId,
    required AttachmentOwnerType ownerType,
    required String ownerId,
    required String localPath,
    required String fileName,
    required String mimeType,
  }) async {
    if (uploadFailure != null) {
      throw uploadFailure!;
    }
    uploads.add(attachmentId);
    final bytes = await File(localPath).readAsBytes();
    remoteFiles[attachmentId] = bytes;
    final digest = sha256.convert(bytes).toString();
    return RemoteAttachment(
      id: attachmentId,
      revision: nextRevision++,
      sha256: forcedSha ?? digest,
      sizeBytes: bytes.length,
      mimeType: mimeType,
    );
  }

  @override
  Future<List<int>> download({
    required String accessToken,
    required String attachmentId,
  }) async {
    if (downloadFailure != null) {
      throw downloadFailure!;
    }
    downloads.add(attachmentId);
    return remoteFiles[attachmentId] ?? const [];
  }

  @override
  Future<void> delete({
    required String accessToken,
    required String attachmentId,
  }) async {
    if (deleteFailure != null) {
      throw deleteFailure!;
    }
    deletes.add(attachmentId);
    remoteFiles.remove(attachmentId);
  }
}
