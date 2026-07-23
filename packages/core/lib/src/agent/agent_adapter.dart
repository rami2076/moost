import '../model/recent_session.dart';

/// セッション要約の対象範囲。
enum SummaryScope {
  /// 直近 N ラリーの抜粋を渡す（高速・低コスト）。
  recent,

  /// セッション全体を対象にする（時間と利用枠を多く消費）。
  full,
}

/// エージェント CLI ごとの差分を閉じ込める抽象インターフェース。
///
/// 吸収する差分は 5 つ（design.md 2 章）:
/// 1. セッション履歴の場所とパース
/// 2. セッションタイトル・メタデータ取得
/// 3. 復帰コマンドの組み立て
/// 4. 要約用ヘッドレス実行コマンド
/// 5. 新規セッション起動コマンドの組み立て（登録プロジェクト用）
///
/// このインターフェースに特定エージェント固有の概念
/// （`~/.claude/` のパス構造、ai-title 等）を漏らさないこと。
abstract interface class AgentAdapter {
  /// エージェント種別の識別子。メモの `agent` フィールドに記録される。
  String get agentId;

  /// UI のバッジ等に出す人間向けの名前（例: "Claude"）。
  String get displayName;

  /// 直近セッション一覧を最新順で返す。タイトル取得まで済ませた状態で返す。
  Future<List<RecentSession>> recentSessions({int limit = 20});

  /// セッションへ復帰するためのシェルコマンドを組み立てる。
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  });

  /// 登録プロジェクトから新規セッションを開始するシェルコマンドを組み立てる。
  /// `buildResumeCommand` と異なり、まだ存在しないセッションを対象にするため
  /// `sessionId` は取らない（CONTEXT.md「登録プロジェクト」、ADR-004）。
  String buildNewSessionCommand({required String projectPath});

  /// セッションを要約して結果テキストを返す。
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  });
}
