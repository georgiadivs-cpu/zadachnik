/// Доменная заметка. Не зависит от Drift и UI.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.contentMarkdown,
    required this.categoryId,
    required this.categoryName,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String contentMarkdown;
  final String? categoryId;
  final String? categoryName;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
}
