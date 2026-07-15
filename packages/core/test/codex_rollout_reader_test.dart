import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory sessionsDir;
  late CodexRolloutReader reader;

  const uuid1 = '019dd8a1-a10c-7ef0-867e-3873d724ec84';
  const uuid2 = '019dd78e-1988-7263-b889-e22cf7d2e5c8';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    sessionsDir = Directory('${tempDir.path}/sessions');
    reader = CodexRolloutReader(sessionsDir: sessionsDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<File> writeRollout(
    String datePath,
    String name,
    List<Object> lines,
  ) async {
    final dir = Directory('${sessionsDir.path}/$datePath');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsString(lines.map(jsonEncode).join('\n'));
    return file;
  }

  Map<String, Object?> sessionMeta(String cwd) => {
        'timestamp': '2026-04-29T09:46:08.089Z',
        'type': 'session_meta',
        'payload': {'id': uuid1, 'cwd': cwd},
      };

  test('missing directory returns empty index', () async {
    expect(await reader.scan(), isEmpty);
  });

  test('scan indexes rollout files by session id across date dirs',
      () async {
    await writeRollout(
      '2026/04/29',
      'rollout-2026-04-29T18-46-04-$uuid1.jsonl',
      [sessionMeta('/p1')],
    );
    await writeRollout(
      '2026/05/01',
      'rollout-2026-05-01T10-00-00-$uuid2.jsonl',
      [sessionMeta('/p2')],
    );

    final index = await reader.scan();
    expect(index.keys, containsAll([uuid1, uuid2]));
  });

  test('scan keeps the newest rollout when a session id appears twice',
      () async {
    await writeRollout(
      '2026/04/29',
      'rollout-2026-04-29T18-46-04-$uuid1.jsonl',
      [sessionMeta('/old')],
    );
    final newer = await writeRollout(
      '2026/05/02',
      'rollout-2026-05-02T09-00-00-$uuid1.jsonl',
      [sessionMeta('/new')],
    );

    final index = await reader.scan();
    expect(index[uuid1]!.path, newer.path);
  });

  test('scan ignores non-rollout files', () async {
    await writeRollout('2026/04/29', 'notes.jsonl', [sessionMeta('/p')]);
    expect(await reader.scan(), isEmpty);
  });

  test('readCwd returns session_meta cwd', () async {
    final file = await writeRollout(
      '2026/04/29',
      'rollout-2026-04-29T18-46-04-$uuid1.jsonl',
      [
        sessionMeta('/Users/u/proj'),
        {'type': 'event_msg', 'payload': {'type': 'task_started'}},
      ],
    );

    expect(await reader.readCwd(file), '/Users/u/proj');
  });

  test('readCwd returns null when session_meta is missing', () async {
    final file = await writeRollout(
      '2026/04/29',
      'rollout-2026-04-29T18-46-04-$uuid1.jsonl',
      [
        {'type': 'event_msg', 'payload': {'type': 'task_started'}},
      ],
    );

    expect(await reader.readCwd(file), isNull);
  });
}
