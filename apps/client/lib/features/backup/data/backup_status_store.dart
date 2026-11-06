import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/backup_models.dart';

class BackupStatusStore {
  BackupStatusStore({this.directory});

  final Directory? directory;

  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/backup_status.json');
  }

  Future<BackupStatusSnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        return null;
      }
      return BackupStatusSnapshot.fromJson(raw);
    } on Object {
      return null;
    }
  }

  Future<void> write(BackupStatusSnapshot status) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(status.toJson()), flush: true);
    } on Object {
      // Кэш не должен мешать работе приложения.
    }
  }
}
