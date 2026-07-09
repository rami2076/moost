import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File memosFile;
  late MemoStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    memosFile = File('${tempDir.path}/v1/memos.json');
    store = MemoStore(memosFile);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Memo buildMemo({String title = 'test memo'}) {
    final now = DateTime.utc(2026, 1, 1);
    return Memo(
      id: generateUuidV4(),
      agent: 'claude-code',
      sessionId: '77e31958-86fe-433e-b1dc-9d9059daa112',
      title: title,
      tags: const ['tag1', 'tag2'],
      body: 'memo body',
      projectPath: '/Users/user/IdeaProjects/works',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('load returns empty list when file does not exist', () async {
    expect(await store.load(), isEmpty);
  });

  test('add and load roundtrip preserves all fields', () async {
    final memo = buildMemo();
    await store.add(memo);

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, memo.id);
    expect(loaded.single.agent, 'claude-code');
    expect(loaded.single.sessionId, memo.sessionId);
    expect(loaded.single.title, memo.title);
    expect(loaded.single.tags, memo.tags);
    expect(loaded.single.body, memo.body);
    expect(loaded.single.projectPath, memo.projectPath);
    expect(loaded.single.createdAt, memo.createdAt);
  });

  test('saved file has schemaVersion envelope and is human readable',
      () async {
    await store.add(buildMemo());

    final json =
        jsonDecode(await memosFile.readAsString()) as Map<String, Object?>;
    expect(json['schemaVersion'], 1);
    expect(json['memos'], isA<List<Object?>>());
    // インデント付き（人が読める）で保存される
    expect(await memosFile.readAsString(), contains('\n  '));
  });

  test('update changes only title/tags/body and updatedAt', () async {
    final memo = buildMemo();
    await store.add(memo);

    final updated = await store.update(
      memo.id,
      title: 'new title',
      tags: ['new'],
      body: 'new body',
    );
    expect(updated, isTrue);

    final loaded = (await store.load()).single;
    expect(loaded.title, 'new title');
    expect(loaded.tags, ['new']);
    expect(loaded.body, 'new body');
    // 不変フィールドは変わらない（ADR-003）
    expect(loaded.id, memo.id);
    expect(loaded.agent, memo.agent);
    expect(loaded.sessionId, memo.sessionId);
    expect(loaded.projectPath, memo.projectPath);
    expect(loaded.createdAt, memo.createdAt);
    expect(loaded.updatedAt.isAfter(memo.updatedAt), isTrue);
  });

  test('update returns false for unknown id', () async {
    expect(await store.update('no-such-id', title: 'x'), isFalse);
  });

  test('delete removes the memo', () async {
    final memo = buildMemo();
    await store.add(memo);

    expect(await store.delete(memo.id), isTrue);
    expect(await store.load(), isEmpty);
    expect(await store.delete(memo.id), isFalse);
  });

  test('corrupt file is quarantined, not overwritten silently', () async {
    await memosFile.parent.create(recursive: true);
    await memosFile.writeAsString('{ this is not json');

    expect(await store.load(), isEmpty);

    // 元ファイルは .corrupt-* に退避されている
    final files = await tempDir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => e.path)
        .toList();
    expect(files.where((p) => p.contains('.corrupt-')), hasLength(1));
  });

  test('multiple memos on the same session are allowed', () async {
    await store.add(buildMemo(title: 'first'));
    await store.add(buildMemo(title: 'second'));

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded.map((m) => m.sessionId).toSet(), hasLength(1));
    expect(loaded.map((m) => m.id).toSet(), hasLength(2));
  });
}
