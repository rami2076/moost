import '../model/recent_session.dart';
import 'agent_adapter.dart';

/// 複数の [AgentAdapter] を束ね、統合した直近セッション一覧と
/// agentId によるルックアップを提供する。
///
/// [AgentAdapter] のインターフェースは単一エージェント前提のまま変えず、
/// 「どの adapter に復帰・要約を頼むか」のルーティングは
/// [RecentSession.agentId] / `Memo.agent` → [byId] で行う。
class AdapterRegistry {
  final List<AgentAdapter> adapters;

  AdapterRegistry(this.adapters)
      : assert(adapters.isNotEmpty, 'at least one adapter is required');

  AgentAdapter? byId(String agentId) {
    for (final adapter in adapters) {
      if (adapter.agentId == agentId) {
        return adapter;
      }
    }
    return null;
  }

  /// 全 adapter の直近セッションを時系列（新しい順）にマージして返す。
  ///
  /// 1 つの adapter の失敗（CLI 未導入・履歴破損等）で一覧全体を
  /// 空にしないよう、失敗した adapter は空扱いにする。
  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    final results = await Future.wait(adapters.map((adapter) async {
      try {
        return await adapter.recentSessions(limit: limit);
      } on Object {
        return const <RecentSession>[];
      }
    }));

    final merged = results.expand((sessions) => sessions).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged.take(limit).toList();
  }
}
