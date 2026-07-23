import 'package:moost_core/moost_core.dart';

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
