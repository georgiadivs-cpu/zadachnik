import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/attachment.dart';

class StoredAttachmentFile {
  const StoredAttachmentFile({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  final String path;
  final int sizeBytes;
  final String sha256;
}

abstract interface class AttachmentFileStore {
  Future<StoredAttachmentFile> store(String id, XFile file);

  Future<String> storeBytes({
    required String id,
    required List<int> bytes,
    required String expectedSha256,
  });

  Future<void> deletePath(String path);

  Future<bool> exists(String path);
}

class AppAttachmentFileStore implements AttachmentFileStore {
  Directory? _directory;

  Future<Directory> _attachmentsDir() async {
    if (_directory != null) {
      return _directory!;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}attachments',
    );
    await dir.create(recursive: true);
    _directory = dir;
    return dir;
  }

  Future<File> _target(String id) async {
    final dir = await _attachmentsDir();
    return File('${dir.path}${Platform.pathSeparator}$id');
  }

  @override
  Future<StoredAttachmentFile> store(String id, XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > AttachmentRules.maxBytes) {
      throw ArgumentError('Файл больше 25 МБ');
    }
    final digest = sha256.convert(bytes).toString();
    final target = await _target(id);
    await target.writeAsBytes(bytes, flush: true);
    return StoredAttachmentFile(
      path: target.path,
      sizeBytes: bytes.length,
      sha256: digest,
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
      throw StateError('Контрольная сумма файла не совпала');
    }
    final target = await _target(id);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<void> deletePath(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String path) => File(path).exists();
}

String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();
