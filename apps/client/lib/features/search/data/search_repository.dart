import 'package:drift/drift.dart' show leftOuterJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../domain/search_result.dart';

abstract interface class SearchRepository {
  Future<List<SearchResult>> search({
    required String query,
    SearchFilter filter = const SearchFilter(),
  });
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return DriftSearchRepository(ref.watch(appDatabaseProvider));
});

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<SearchResult>> search({
    required String query,
    SearchFilter filter = const SearchFilter(),
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }

    final results = <SearchResult>[];
    if (filter.type != SearchResultType.task && !filter.highPriority) {
      results.addAll(await _searchNotes(normalized, filter));
    }
    if (filter.type != SearchResultType.note) {
      results.addAll(await _searchTasks(normalized, filter));
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) {
        return byUpdated;
      }
      return a.title.compareTo(b.title);
    });
    return results.take(100).toList();
  }

  Future<List<SearchResult>> _searchNotes(
    String query,
    SearchFilter filter,
  ) async {
    final rows = await (_database.select(_database.notes).join([
      leftOuterJoin(
        _database.categories,
        _database.categories.id.equalsExp(_database.notes.categoryId),
      ),
    ])..where(_database.notes.deletedAt.isNull())).get();

    final results = <SearchResult>[];
    for (final row in rows) {
      final note = row.readTable(_database.notes);
      final category = row.readTableOrNull(_database.categories);
      if (filter.categoryId != null && note.categoryId != filter.categoryId) {
        continue;
      }
      final titleMatched = note.title.toLowerCase().contains(query);
      final bodyMatched = note.contentMarkdown.toLowerCase().contains(query);
      final categoryMatched = (category?.name ?? '').toLowerCase().contains(
        query,
      );
      if (!titleMatched && !bodyMatched && !categoryMatched) {
        continue;
      }
      final exactTitle = note.title.toLowerCase() == query;
      results.add(
        SearchResult(
          type: SearchResultType.note,
          id: note.id,
          title: note.title,
          body: _snippet(note.contentMarkdown, query),
          categoryId: note.categoryId,
          categoryName: category?.name,
          laneName: null,
          priority: null,
          reminderAt: null,
          isCancelled: false,
          updatedAt: note.updatedAt.toUtc(),
          titleMatched: titleMatched,
          score:
              (titleMatched ? (exactTitle ? 5 : 3) : 0) +
              (bodyMatched ? 2 : 0) +
              (categoryMatched ? 1 : 0),
        ),
      );
    }
    return results;
  }

  Future<List<SearchResult>> _searchTasks(
    String query,
    SearchFilter filter,
  ) async {
    final rows = await (_database.select(_database.tasks).join([
      leftOuterJoin(
        _database.lanes,
        _database.lanes.id.equalsExp(_database.tasks.laneId),
      ),
      leftOuterJoin(
        _database.categories,
        _database.categories.id.equalsExp(_database.tasks.categoryId),
      ),
    ])..where(_database.tasks.deletedAt.isNull())).get();
    final reminders = await (_database.select(
      _database.taskReminders,
    )..where((table) => table.deletedAt.isNull())).get();
    final reminderByTask = {
      for (final reminder in reminders) reminder.taskId: reminder,
    };

    final results = <SearchResult>[];
    for (final row in rows) {
      final task = row.readTable(_database.tasks);
      final lane = row.readTableOrNull(_database.lanes);
      final category = row.readTableOrNull(_database.categories);
      if (filter.categoryId != null && task.categoryId != filter.categoryId) {
        continue;
      }
      if (filter.highPriority && task.priority != 'HIGH') {
        continue;
      }
      final titleMatched = task.title.toLowerCase().contains(query);
      final bodyMatched = task.description.toLowerCase().contains(query);
      final laneMatched = (lane?.name ?? '').toLowerCase().contains(query);
      final categoryMatched = (category?.name ?? '').toLowerCase().contains(
        query,
      );
      if (!titleMatched && !bodyMatched && !laneMatched && !categoryMatched) {
        continue;
      }
      final exactTitle = task.title.toLowerCase() == query;
      results.add(
        SearchResult(
          type: SearchResultType.task,
          id: task.id,
          title: task.title,
          body: _snippet(task.description, query),
          categoryId: task.categoryId,
          categoryName: category?.name,
          laneName: lane?.name,
          priority: task.priority,
          reminderAt: reminderByTask[task.id]?.remindAt.toUtc(),
          isCancelled: task.systemState == 'CANCELLED',
          updatedAt: task.updatedAt.toUtc(),
          titleMatched: titleMatched,
          score:
              (titleMatched ? (exactTitle ? 5 : 3) : 0) +
              (bodyMatched ? 2 : 0) +
              (laneMatched ? 1 : 0) +
              (categoryMatched ? 1 : 0),
        ),
      );
    }
    return results;
  }

  static String _snippet(String value, String query) {
    final text = value.trim();
    if (text.isEmpty) {
      return '';
    }
    final lines = text.split(RegExp(r'\r?\n'));
    final matching = lines.where((line) => line.toLowerCase().contains(query));
    final source = matching.isNotEmpty
        ? matching.first
        : lines.firstWhere(
            (line) => line.trim().isNotEmpty,
            orElse: () => text,
          );
    final compact = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 180 ? compact : '${compact.substring(0, 177)}…';
  }
}
