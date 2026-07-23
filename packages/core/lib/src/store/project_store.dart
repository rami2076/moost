import 'dart:io';

import '../model/project.dart';
import 'json_file_store.dart';

/// `~/.moost/v1/projects.json` の CRUD。
///
/// エンベロープ形式は `{"schemaVersion": 1, "projects": [...]}`。
/// 登録プロジェクトは編集できるフィールドを持たないため、update はない
/// （requirements.md 3.8）。
class ProjectStore {
  static const schemaVersion = 1;

  final JsonFileStore _store;

  ProjectStore(File file) : _store = JsonFileStore(file);

  /// デフォルトの保存先（`~/.moost/v1/projects.json`）を使う。
  factory ProjectStore.defaultLocation() {
    final home = Platform.environment['HOME'] ?? '';
    return ProjectStore(File('$home/.moost/v1/projects.json'));
  }

  Future<List<Project>> load() async {
    final json = await _store.read();
    if (json == null) {
      return [];
    }
    final rawProjects = json['projects'];
    if (rawProjects is! List<Object?>) {
      return [];
    }
    final projects = <Project>[];
    for (final raw in rawProjects) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      try {
        projects.add(Project.fromJson(raw));
      } on Object {
        // 壊れた 1 件のためにストア全体を捨てない
        continue;
      }
    }
    return projects;
  }

  Future<void> add(Project project) async {
    final projects = await load();
    projects.add(project);
    await _save(projects);
  }

  Future<bool> delete(String id) async {
    final projects = await load();
    final before = projects.length;
    projects.removeWhere((project) => project.id == id);
    if (projects.length == before) {
      return false;
    }
    await _save(projects);
    return true;
  }

  Future<void> _save(List<Project> projects) => _store.write({
        'schemaVersion': schemaVersion,
        'projects': projects.map((project) => project.toJson()).toList(),
      });
}
