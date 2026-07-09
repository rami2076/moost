import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File historyFile;
  late SessionHistoryReader reader;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    historyFile = File('${tempDir.path}/history.jsonl');
    reader = SessionHistoryReader(
      historyFile: historyFile,
      excludeMarker: '[Moost要約]',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String line({
    required String display,
    required int timestamp,
    String project = '/Users/u/proj',
    required String sessionId,
  }) {
    return jsonEncode({
      'display': display,
      'pastedContents': <String, Object?>{},
      'timestamp': timestamp,
      'project': project,
      'sessionId': sessionId,
    });
  }

  test('returns empty list when history file does not exist', () async {
    expect(await reader.recentSessions(), isEmpty);
  });

  test('aggregates by sessionId keeping the latest prompt', () async {
    await historyFile.writeAsString([
      line(display: 'first prompt', timestamp: 1000, sessionId: 'aaa'),
      line(display: 'second prompt', timestamp: 2000, sessionId: 'aaa'),
      line(display: 'other session', timestamp: 1500, sessionId: 'bbb'),
    ].join('\n'));

    final sessions = await reader.recentSessions();
    expect(sessions, hasLength(2));
    // 最新順にソートされる
    expect(sessions[0].sessionId, 'aaa');
    expect(sessions[0].lastPrompt, 'second prompt');
    expect(sessions[1].sessionId, 'bbb');
  });

  test('skips unparseable lines without crashing', () async {
    await historyFile.writeAsString([
      'this is not json at all',
      '{"broken": true}',
      '{"display": 123, "timestamp": "x", "project": 1, "sessionId": 2}',
      line(display: 'valid', timestamp: 1000, sessionId: 'aaa'),
      '',
    ].join('\n'));

    final sessions = await reader.recentSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.lastPrompt, 'valid');
  });

  test('excludes summary fork sessions by marker prefix', () async {
    await historyFile.writeAsString([
      line(display: 'normal work', timestamp: 1000, sessionId: 'aaa'),
      line(
        display: '[Moost要約] このセッションを要約して',
        timestamp: 2000,
        sessionId: 'fork-session',
      ),
    ].join('\n'));

    final sessions = await reader.recentSessions();
    expect(sessions.map((s) => s.sessionId), ['aaa']);
  });

  test('respects limit after sorting', () async {
    await historyFile.writeAsString([
      for (var i = 0; i < 10; i++)
        line(display: 'p$i', timestamp: i * 100, sessionId: 's$i'),
    ].join('\n'));

    final sessions = await reader.recentSessions(limit: 3);
    expect(sessions.map((s) => s.sessionId), ['s9', 's8', 's7']);
  });

  test('converts timestamp to updatedAt', () async {
    final ts = DateTime.utc(2026, 7, 9, 12).millisecondsSinceEpoch;
    await historyFile
        .writeAsString(line(display: 'p', timestamp: ts, sessionId: 'a'));

    final sessions = await reader.recentSessions();
    expect(sessions.single.updatedAt, DateTime.utc(2026, 7, 9, 12));
  });
}
