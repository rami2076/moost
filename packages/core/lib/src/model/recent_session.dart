/// 直近セッション一覧の 1 行分の表示データ。
class RecentSession {
  final String sessionId;
  final String projectPath;

  /// そのセッションで最後に打ったプロンプト。
  final String lastPrompt;

  final DateTime updatedAt;

  /// エージェント自身が生成したセッションタイトル（Claude Code の ai-title）。
  /// 取得できなかった場合は null。
  final String? aiTitle;

  const RecentSession({
    required this.sessionId,
    required this.projectPath,
    required this.lastPrompt,
    required this.updatedAt,
    this.aiTitle,
  });

  static const _fallbackTitleLength = 50;

  /// セッションタイトル。ai-title があればそれ、なければ最終プロンプト先頭 50 文字。
  String get displayTitle {
    final title = aiTitle;
    if (title != null && title.isNotEmpty) {
      return title;
    }
    // substring はサロゲートペア（絵文字等）を分断するため runes で切る
    final runes = lastPrompt.runes;
    if (runes.length <= _fallbackTitleLength) {
      return lastPrompt;
    }
    return String.fromCharCodes(runes.take(_fallbackTitleLength));
  }

  RecentSession withAiTitle(String? aiTitle) => RecentSession(
        sessionId: sessionId,
        projectPath: projectPath,
        lastPrompt: lastPrompt,
        updatedAt: updatedAt,
        aiTitle: aiTitle,
      );
}
