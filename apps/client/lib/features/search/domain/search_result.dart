enum SearchResultType { note, task }

class SearchResult {
  const SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.body,
    required this.categoryId,
    required this.categoryName,
    required this.laneName,
    required this.priority,
    required this.reminderAt,
    required this.isCancelled,
    required this.updatedAt,
    required this.titleMatched,
    required this.score,
  });

  final SearchResultType type;
  final String id;
  final String title;
  final String body;
  final String? categoryId;
  final String? categoryName;
  final String? laneName;
  final String? priority;
  final DateTime? reminderAt;
  final bool isCancelled;
  final DateTime updatedAt;
  final bool titleMatched;
  final int score;
}

class SearchFilter {
  const SearchFilter({this.type, this.categoryId, this.highPriority = false});

  final SearchResultType? type;
  final String? categoryId;
  final bool highPriority;
}
