import 'package:moost_core/moost_core.dart';

/// メモリ上で完結する [MemoRepository] のフェイク（テスト用）。
class FakeMemoStore implements MemoRepository {
  final List<Memo> _memos;

  FakeMemoStore([List<Memo>? initial]) : _memos = List.of(initial ?? const []);

  @override
  Future<List<Memo>> load() async => List.of(_memos);

  @override
  Future<void> add(Memo memo) async {
    _memos.add(memo);
  }

  @override
  Future<bool> update(
    String id, {
    String? title,
    List<String>? tags,
    String? body,
  }) async {
    final index = _memos.indexWhere((memo) => memo.id == id);
    if (index < 0) {
      return false;
    }
    _memos[index] = _memos[index].updateUserFields(
      title: title,
      tags: tags,
      body: body,
      updatedAt: DateTime.now().toUtc(),
    );
    return true;
  }

  @override
  Future<bool> delete(String id) async {
    final before = _memos.length;
    _memos.removeWhere((memo) => memo.id == id);
    return _memos.length != before;
  }
}

/// メモリ上で完結する [ProjectRepository] のフェイク（テスト用）。
class FakeProjectStore implements ProjectRepository {
  final List<Project> _projects;

  FakeProjectStore([List<Project>? initial])
      : _projects = List.of(initial ?? const []);

  @override
  Future<List<Project>> load() async => List.of(_projects);

  @override
  Future<void> add(Project project) async {
    _projects.add(project);
  }

  @override
  Future<bool> delete(String id) async {
    final before = _projects.length;
    _projects.removeWhere((project) => project.id == id);
    return _projects.length != before;
  }
}

/// [AgentAdapter] のフェイク（テスト用）。
class FakeAdapter implements AgentAdapter {
  @override
  final String agentId;

  final List<RecentSession> _sessions;

  FakeAdapter(this.agentId, [List<RecentSession>? sessions])
      : _sessions = sessions ?? const [];

  @override
  String get displayName => agentId;

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async =>
      _sessions.take(limit).toList();

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) =>
      '$agentId resume $sessionId in $projectPath';

  @override
  String buildNewSessionCommand({required String projectPath}) =>
      '$agentId new $projectPath';

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async =>
      'summary';
}
