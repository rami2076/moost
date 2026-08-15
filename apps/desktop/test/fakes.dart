import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/src/mcp/mcp_binary_locator.dart';
import 'package:moost_desktop/src/mcp/mcp_setup_service.dart';

/// メモリ上で完結する [MemoRepository] のフェイク（widget テスト用）。
///
/// 実ファイル I/O を一切行わないため、保存 → 再読込のたびに実時間の
/// 完了待ちが必要だった問題（Issue #30）がそもそも起きない。
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

/// メモリ上で完結する [ProjectRepository] のフェイク（widget テスト用）。
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

/// メモリ上で完結する [SettingsRepository] のフェイク（widget テスト用）。
class FakeSettingsStore implements SettingsRepository {
  Settings _settings;

  FakeSettingsStore([Settings? initial]) : _settings = initial ?? const Settings();

  @override
  Future<Settings> load() async => _settings;

  @override
  Future<void> save(Settings settings) async {
    _settings = settings;
  }
}

/// 実バイナリなしで「同梱バイナリが見つかった」状態を再現する
/// [McpBinaryLocator] のフェイク（widget テスト用）。
class FakeMcpBinaryLocator implements McpBinaryLocator {
  final bool binaryExists;

  FakeMcpBinaryLocator({this.binaryExists = true});

  @override
  String get binaryPath => '/fake/Moost.app/Contents/Resources/moost-mcp';

  @override
  Future<bool> exists() async => binaryExists;
}

/// 実プロセスを一切起動しない [McpSetupService] のフェイク（widget テスト用）。
///
/// 呼び出された対象を記録し、[failWith] が設定されていればその対象への
/// 呼び出しだけ [McpSetupException] を投げる。
class FakeMcpSetupService implements McpSetupService {
  final List<String> calls = [];
  final Map<String, String> failWith;
  final bool testConnectionResult;

  /// 実サービスと同様、register* が成功すると対応する is*Connected が
  /// true を返すようになる（設定画面が「連携済み」表示へ切り替わる
  /// 挙動をテストで再現するため）。
  bool claudeCodeConnected;
  bool codexConnected;
  bool claudeDesktopConnected;

  FakeMcpSetupService({
    this.failWith = const {},
    this.testConnectionResult = true,
    this.claudeCodeConnected = false,
    this.codexConnected = false,
    this.claudeDesktopConnected = false,
  });

  Future<void> _record(String target, {required bool connectedAfter}) async {
    calls.add(target);
    final message = failWith[target];
    if (message != null) {
      throw McpSetupException(message);
    }
    switch (target) {
      case 'claude-code':
        claudeCodeConnected = connectedAfter;
      case 'codex':
        codexConnected = connectedAfter;
      case 'claude-desktop':
        claudeDesktopConnected = connectedAfter;
    }
  }

  @override
  Future<void> registerClaudeCode(String binaryPath) =>
      _record('claude-code', connectedAfter: true);

  @override
  Future<void> registerCodex(String binaryPath) =>
      _record('codex', connectedAfter: true);

  @override
  Future<void> registerClaudeDesktop(String binaryPath) =>
      _record('claude-desktop', connectedAfter: true);

  @override
  Future<void> unregisterClaudeCode() =>
      _record('claude-code', connectedAfter: false);

  @override
  Future<void> unregisterCodex() =>
      _record('codex', connectedAfter: false);

  @override
  Future<void> unregisterClaudeDesktop() =>
      _record('claude-desktop', connectedAfter: false);

  @override
  Future<bool> isClaudeCodeConnected() async => claudeCodeConnected;

  @override
  Future<bool> isCodexConnected() async => codexConnected;

  @override
  Future<bool> isClaudeDesktopConnected() async => claudeDesktopConnected;

  @override
  Future<bool> testConnection(String binaryPath,
      {Duration timeout = const Duration(seconds: 5)}) async {
    calls.add('test-connection');
    return testConnectionResult;
  }
}
