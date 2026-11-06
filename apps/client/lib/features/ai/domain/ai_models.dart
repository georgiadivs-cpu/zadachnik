enum AiChangeType {
  moveTask,
  updateTaskDates,
  addReminder,
  createNote,
  appendNote,
}

class AiChange {
  const AiChange({
    required this.type,
    required this.targetId,
    required this.targetTitle,
    required this.field,
    required this.before,
    required this.after,
    required this.data,
  });

  final AiChangeType type;
  final String? targetId;
  final String targetTitle;
  final String field;
  final String before;
  final String after;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'targetId': targetId,
    'targetTitle': targetTitle,
    'field': field,
    'before': before,
    'after': after,
    'data': data,
  };

  factory AiChange.fromJson(Map<String, dynamic> json) => AiChange(
    type: AiChangeType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => AiChangeType.createNote,
    ),
    targetId: json['targetId'] as String?,
    targetTitle: json['targetTitle'] as String? ?? '',
    field: json['field'] as String? ?? '',
    before: json['before'] as String? ?? '',
    after: json['after'] as String? ?? '',
    data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

class AiProposal {
  const AiProposal({
    required this.id,
    required this.prompt,
    required this.title,
    required this.explanation,
    required this.impact,
    required this.changes,
  });

  final String id;
  final String prompt;
  final String title;
  final String explanation;
  final String impact;
  final List<AiChange> changes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'title': title,
    'explanation': explanation,
    'impact': impact,
    'changes': changes.map((change) => change.toJson()).toList(),
  };

  factory AiProposal.fromJson(Map<String, dynamic> json) => AiProposal(
    id: json['id'] as String,
    prompt: json['prompt'] as String? ?? '',
    title: json['title'] as String? ?? 'Предложение',
    explanation: json['explanation'] as String? ?? '',
    impact: json['impact'] as String? ?? '',
    changes: (json['changes'] as List<dynamic>? ?? const [])
        .map((item) => AiChange.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class AiResponse {
  const AiResponse({required this.message, this.proposal});

  final String message;
  final AiProposal? proposal;
}

class AiApplyResult {
  const AiApplyResult({
    required this.success,
    required this.message,
    this.stale = false,
  });

  final bool success;
  final String message;
  final bool stale;
}

class AiStaleProposal implements Exception {
  const AiStaleProposal(this.message);

  final String message;
}

class AiJournalEntry {
  const AiJournalEntry({
    required this.id,
    required this.prompt,
    required this.title,
    required this.status,
    required this.message,
    required this.error,
    required this.createdAt,
    required this.decidedAt,
    required this.executedAt,
  });

  final String id;
  final String prompt;
  final String title;
  final String status;
  final String? message;
  final String? error;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final DateTime? executedAt;
}
