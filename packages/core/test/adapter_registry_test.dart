import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  RecentSession session(String agentId, String id, DateTime updatedAt) {
    return RecentSession(
      agentId: agentId,
      sessionId: id,
      projectPath: '/p',
      lastPrompt: 'prompt $id',
      updatedAt: updatedAt,
    );
  }

  test('byId finds the adapter and returns null for unknown ids', () {
    final claude = _FakeAdapter('claude-code', []);
    final codex = _FakeAdapter('codex', []);
    final registry = AdapterRegistry([claude, codex]);

    expect(registry.byId('codex'), same(codex));
    expect(registry.byId('claude-code'), same(claude));
    expect(registry.byId('gemini'), isNull);
  });

  test('recentSessions merges adapters newest-first and applies limit',
      () async {
    final registry = AdapterRegistry([
      _FakeAdapter('a', [
        session('a', 'a1', DateTime.utc(2026, 7, 3)),
        session('a', 'a2', DateTime.utc(2026, 7, 1)),
      ]),
      _FakeAdapter('b', [
        session('b', 'b1', DateTime.utc(2026, 7, 4)),
        session('b', 'b2', DateTime.utc(2026, 7, 2)),
      ]),
    ]);

    final merged = await registry.recentSessions(limit: 3);
    expect(merged.map((s) => s.sessionId), ['b1', 'a1', 'b2']);
  });

  test('a failing adapter does not break the merged list', () async {
    final registry = AdapterRegistry([
      _FakeAdapter('broken', [], throws: true),
      _FakeAdapter('ok', [session('ok', 's1', DateTime.utc(2026))]),
    ]);

    final merged = await registry.recentSessions();
    expect(merged.map((s) => s.sessionId), ['s1']);
  });
}

class _FakeAdapter implements AgentAdapter {
  @override
  final String agentId;

  final List<RecentSession> _sessions;
  final bool throws;

  _FakeAdapter(this.agentId, this._sessions, {this.throws = false});

  @override
  String get displayName => agentId;

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    if (throws) {
      throw StateError('broken adapter');
    }
    return _sessions.take(limit).toList();
  }

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) =>
      '$agentId resume $sessionId';

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async =>
      'summary';
}
