import 'agent/agent_adapter.dart';

/// セッション要約のメモリキャッシュ（design.md 5 章 / ADR-002）。
///
/// 要約は永続化せず、アプリ常駐中のみ生きる。目的は同じセッション詳細を
/// 開き直したときに `claude -p` を再実行しないこと（時間と利用料の節約）。
/// キーは セッションID × 要約範囲（scope + ラリー数）。
class SummaryCache {
  final Map<String, String> _entries = {};

  static String _key(String sessionId, SummaryScope scope, int rallies) {
    return switch (scope) {
      SummaryScope.full => '$sessionId:full',
      SummaryScope.recent => '$sessionId:recent$rallies',
    };
  }

  String? get(String sessionId, SummaryScope scope, int rallies) {
    return _entries[_key(sessionId, scope, rallies)];
  }

  void put(
    String sessionId,
    SummaryScope scope,
    int rallies,
    String summary,
  ) {
    _entries[_key(sessionId, scope, rallies)] = summary;
  }

  void clear() => _entries.clear();
}
