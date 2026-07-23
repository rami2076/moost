/// ユーザーが新規セッション起動のために明示的に登録したディレクトリ。
///
/// メモと異なりセッションに紐づかず、`agent` も持たない。セッションが1件も
/// ないディレクトリでも登録できる（CONTEXT.md「登録プロジェクト」、ADR-004）。
class Project {
  final String id;
  final String projectPath;
  final DateTime createdAt;

  const Project({
    required this.id,
    required this.projectPath,
    required this.createdAt,
  });

  /// 一覧表示用の名前。`projectPath` の最後のディレクトリ名を都度導出する
  /// （保存はしない。requirements.md 3.8）。
  String get displayName {
    final trimmed = projectPath.endsWith('/')
        ? projectPath.substring(0, projectPath.length - 1)
        : projectPath;
    final segment = trimmed.split('/').last;
    return segment.isEmpty ? projectPath : segment;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'projectPath': projectPath,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory Project.fromJson(Map<String, Object?> json) {
    return Project(
      id: json['id'] as String,
      projectPath: json['projectPath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
