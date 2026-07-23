import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory codexHome;
  late CodexAdapter adapter;

  const uuid1 = '019dd8a1-a10c-7ef0-867e-3873d724ec84';
  const uuid2 = '019dd78e-1988-7263-b889-e22cf7d2e5c8';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    codexHome = Directory('${tempDir.path}/codex_home');
    await codexHome.create();
    adapter = CodexAdapter(codexHome: codexHome.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> writeHistory(List<Map<String, Object?>> lines) async {
    await File('${codexHome.path}/history.jsonl')
        .writeAsString(lines.map(jsonEncode).join('\n'));
  }

  Future<void> writeRollout(String sessionId, String cwd) async {
    final dir = Directory('${codexHome.path}/sessions/2026/04/29');
    await dir.create(recursive: true);
    await File('${dir.path}/rollout-2026-04-29T10-00-00-$sessionId.jsonl')
        .writeAsString(jsonEncode({
      'type': 'session_meta',
      'payload': {'id': sessionId, 'cwd': cwd},
    }));
  }

  test('agent identity', () {
    expect(adapter.agentId, 'codex');
    expect(adapter.displayName, 'Codex');
  });

  test('recentSessions joins history with rollout cwd', () async {
    await writeHistory([
      {'session_id': uuid1, 'ts': 200, 'text': 'newer prompt'},
      {'session_id': uuid2, 'ts': 100, 'text': 'older prompt'},
    ]);
    await writeRollout(uuid1, '/Users/u/proj1');
    await writeRollout(uuid2, '/Users/u/proj2');

    final sessions = await adapter.recentSessions();
    expect(sessions, hasLength(2));
    expect(sessions[0].agentId, 'codex');
    expect(sessions[0].sessionId, uuid1);
    expect(sessions[0].projectPath, '/Users/u/proj1');
    expect(sessions[0].lastPrompt, 'newer prompt');
    // Codex に ai-title 相当はないので lastPrompt がタイトルになる
    expect(sessions[0].displayTitle, 'newer prompt');
    expect(sessions[1].projectPath, '/Users/u/proj2');
  });

  test('recentSessions drops sessions whose rollout is gone', () async {
    await writeHistory([
      {'session_id': uuid1, 'ts': 200, 'text': 'has rollout'},
      {'session_id': uuid2, 'ts': 100, 'text': 'rollout deleted'},
    ]);
    await writeRollout(uuid1, '/p');

    final sessions = await adapter.recentSessions();
    expect(sessions.map((s) => s.sessionId), [uuid1]);
  });

  test('recentSessions respects the limit', () async {
    await writeHistory([
      for (var i = 0; i < 5; i++)
        {
          'session_id': '0000000$i-0000-0000-0000-000000000000',
          'ts': 100 + i,
          'text': 'p$i',
        },
    ]);
    for (var i = 0; i < 5; i++) {
      await writeRollout('0000000$i-0000-0000-0000-000000000000', '/p$i');
    }

    final sessions = await adapter.recentSessions(limit: 3);
    expect(sessions, hasLength(3));
    expect(sessions.first.lastPrompt, 'p4');
  });

  test('missing codex home returns empty list', () async {
    final empty = CodexAdapter(codexHome: '${tempDir.path}/nope');
    expect(await empty.recentSessions(), isEmpty);
  });

  test('buildResumeCommand escapes and cds into the project', () {
    final command = adapter.buildResumeCommand(
      projectPath: "/Users/u/my proj",
      sessionId: uuid1,
    );
    expect(command, "cd '/Users/u/my proj' && codex resume '$uuid1'");
  });

  test('buildResumeCommand omits cd when the project path is unknown', () {
    final command = adapter.buildResumeCommand(
      projectPath: '',
      sessionId: uuid1,
    );
    expect(command, "codex resume '$uuid1'");
  });

  test('buildNewSessionCommand escapes and cds into the project, no resume',
      () {
    final command =
        adapter.buildNewSessionCommand(projectPath: '/Users/u/my proj');
    expect(command, "cd '/Users/u/my proj' && codex");
  });
}
