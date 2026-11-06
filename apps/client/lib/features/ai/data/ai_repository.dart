import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ai_models.dart';

class AiRepository {
  AiRepository(this._database);

  final AppDatabase _database;

  Future<void> createProposal(AiProposal proposal) async {
    await _database
        .into(_database.aiActions)
        .insert(
          AiActionsCompanion.insert(
            id: proposal.id,
            prompt: proposal.prompt,
            proposal: jsonEncode(proposal.toJson()),
            status: 'PROPOSED',
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> markDecided({
    required String id,
    required String status,
    String? message,
    String? error,
    bool executed = false,
  }) async {
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.aiActions,
    )..where((table) => table.id.equals(id))).write(
      AiActionsCompanion(
        status: Value(status),
        message: Value(message),
        error: Value(error),
        decidedAt: Value(now),
        executedAt: Value(executed ? now : null),
      ),
    );
  }

  Stream<List<AiJournalEntry>> watchRecent() {
    final query = _database.select(_database.aiActions)
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(20);
    return query.watch().map((rows) => rows.map(_journal).toList());
  }

  static AiJournalEntry _journal(AiActionRow row) {
    String title = 'Предложение';
    try {
      final data = jsonDecode(row.proposal) as Map<String, dynamic>;
      title = data['title'] as String? ?? title;
    } on Object {
      // Повреждённая запись журнала не должна ломать экран.
    }
    return AiJournalEntry(
      id: row.id,
      prompt: row.prompt,
      title: title,
      status: row.status,
      message: row.message,
      error: row.error,
      createdAt: row.createdAt.toUtc(),
      decidedAt: row.decidedAt?.toUtc(),
      executedAt: row.executedAt?.toUtc(),
    );
  }
}
