/// 人がセッションに付ける記録。
///
/// 復帰に必要な情報（[sessionId] + [projectPath]）を自己完結で持つため、
/// エージェント側の履歴から元セッションが消えた後でもメモからの復帰が機能する。
/// 編集で変更できるのは [title] / [tags] / [body] のみ（ADR-003）。
class Memo {
  final String id;
  final String agent;
  final String sessionId;
  final String title;
  final List<String> tags;
  final String body;
  final String projectPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo({
    required this.id,
    required this.agent,
    required this.sessionId,
    required this.title,
    required List<String> tags,
    required this.body,
    required this.projectPath,
    required this.createdAt,
    required this.updatedAt,
  }) : tags = List.unmodifiable(tags);

  /// 可変フィールド（title / tags / body）だけを差し替えたコピーを返す。
  /// updatedAt は必ず更新される。
  Memo updateUserFields({
    String? title,
    List<String>? tags,
    String? body,
    required DateTime updatedAt,
  }) {
    return Memo(
      id: id,
      agent: agent,
      sessionId: sessionId,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      body: body ?? this.body,
      projectPath: projectPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'agent': agent,
        'sessionId': sessionId,
        'title': title,
        'tags': tags,
        'body': body,
        'projectPath': projectPath,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Memo.fromJson(Map<String, Object?> json) {
    return Memo(
      id: json['id'] as String,
      agent: json['agent'] as String,
      sessionId: json['sessionId'] as String,
      title: json['title'] as String,
      tags: (json['tags'] as List<Object?>).cast<String>(),
      body: json['body'] as String,
      projectPath: json['projectPath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// カンマ区切りのタグ入力を分割・トリム・空要素除去して配列にする。
List<String> parseTags(String input) => input
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList();
