import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File projectsFile;
  late ProjectStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    projectsFile = File('${tempDir.path}/v1/projects.json');
    store = ProjectStore(projectsFile);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Project buildProject({String projectPath = '/Users/user/IdeaProjects/moost'}) {
    return Project(
      id: generateUuidV4(),
      projectPath: projectPath,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('load returns empty list when file does not exist', () async {
    expect(await store.load(), isEmpty);
  });

  test('add and load roundtrip preserves all fields', () async {
    final project = buildProject();
    await store.add(project);

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, project.id);
    expect(loaded.single.projectPath, project.projectPath);
    expect(loaded.single.createdAt, project.createdAt);
  });

  test('saved file has schemaVersion envelope and is human readable',
      () async {
    await store.add(buildProject());

    final json = jsonDecode(await projectsFile.readAsString())
        as Map<String, Object?>;
    expect(json['schemaVersion'], 1);
    expect(json['projects'], isA<List<Object?>>());
    expect(await projectsFile.readAsString(), contains('\n  '));
  });

  test('displayName derives the last path segment', () async {
    expect(buildProject(projectPath: '/Users/user/dev/moost').displayName,
        'moost');
    expect(buildProject(projectPath: '/Users/user/dev/moost/').displayName,
        'moost');
    expect(buildProject(projectPath: '/').displayName, '/');
  });

  test('delete removes the project', () async {
    final project = buildProject();
    await store.add(project);

    expect(await store.delete(project.id), isTrue);
    expect(await store.load(), isEmpty);
    expect(await store.delete(project.id), isFalse);
  });

  test('duplicate paths are allowed', () async {
    await store.add(buildProject());
    await store.add(buildProject());

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded.map((p) => p.id).toSet(), hasLength(2));
  });

  test('corrupt file is quarantined, not overwritten silently', () async {
    await projectsFile.parent.create(recursive: true);
    await projectsFile.writeAsString('{ this is not json');

    expect(await store.load(), isEmpty);

    final files = await tempDir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => e.path)
        .toList();
    expect(files.where((p) => p.contains('.corrupt-')), hasLength(1));
  });
}
