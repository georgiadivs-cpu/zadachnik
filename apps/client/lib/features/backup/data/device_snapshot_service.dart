import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';

class PreparedSnapshot {
  const PreparedSnapshot({
    required this.path,
    required this.sha256,
    required this.sizeBytes,
    required this.schemaVersion,
  });

  final String path;
  final String sha256;
  final int sizeBytes;
  final int schemaVersion;
}

class SnapshotExportFailure implements Exception {
  const SnapshotExportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeviceSnapshotService {
  DeviceSnapshotService(this._database, {this.tempDirectory});

  final AppDatabase _database;
  final Directory? tempDirectory;

  static const maxBytes = 256 * 1024 * 1024;

  Future<PreparedSnapshot> prepare() async {
    final directory = tempDirectory ?? await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '${directory.path}/zadachnik-snapshot-$stamp.db';
    final escaped = path.replaceAll("'", "''");
    try {
      await _database.customStatement("VACUUM INTO '$escaped'");
    } on Object catch (error) {
      throw SnapshotExportFailure('Не удалось подготовить снимок: $error');
    }
    final file = File(path);
    try {
      if (!await file.exists()) {
        throw const SnapshotExportFailure('Снимок SQLite не создан');
      }
      final size = await file.length();
      if (size <= 0) {
        throw const SnapshotExportFailure('Снимок SQLite пуст');
      }
      if (size > maxBytes) {
        throw const SnapshotExportFailure('Снимок больше 256 МБ');
      }
      return PreparedSnapshot(
        path: path,
        sha256: await _sha256(file),
        sizeBytes: size,
        schemaVersion: _database.schemaVersion,
      );
    } on SnapshotExportFailure {
      try {
        await file.delete();
      } on Object {
        // Временный файл удалит система.
      }
      rethrow;
    } on Object catch (error) {
      try {
        await file.delete();
      } on Object {
        // Временный файл удалит система.
      }
      throw SnapshotExportFailure('Не удалось прочитать снимок: $error');
    }
  }

  Future<void> discard(PreparedSnapshot snapshot) async {
    try {
      await File(snapshot.path).delete();
    } on Object {
      // Временный файл удалит система.
    }
  }

  static Future<String> _sha256(File file) async {
    final sink = _DigestSink();
    final converter = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    return sink.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
