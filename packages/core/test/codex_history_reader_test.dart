import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File historyFile;
  late CodexHistoryReader reader;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    historyFile = File('${tempDir.path}/history.jsonl');
    reader = CodexHistoryReader(
      historyFile: historyFile,
      excludeMarker: '[Moost要約]',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String line({
    required String sessionId,
    required int ts,
    required String text,
  }) {
    return jsonEncode({'session_id': sessionId, 'ts': ts, 'text': text});
  }

  test('missing file returns empty list', () async {
    expect(await reader.aggregatedEntries(), isEmpty);
  });

  test('aggregates by session and keeps the latest prompt', () async {
    await historyFile.writeAsString([
      line(sessionId: 's1', ts: 100, text: 'first'),
      line(sessionId: 's2', ts: 150, text: 'other session'),
      line(sessionId: 's1', ts: 200, text: 'latest'),
    ].join('\n'));

    final entries = await reader.aggregatedEntries();
    expect(entries, hasLength(2));
    // 新しい順
    expect(entries[0].sessionId, 's1');
    expect(entries[0].lastPrompt, 'latest');
    expect(entries[1].sessionId, 's2');
  });

  test('converts ts seconds to UTC DateTime', () async {
    await historyFile.writeAsString(
      line(sessionId: 's1', ts: 1700000000, text: 'p'),
    );

    final entries = await reader.aggregatedEntries();
    expect(
      entries.single.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
  });

  test('excludes sessions whose prompt starts with the marker', () async {
    await historyFile.writeAsString([
      line(sessionId: 's1', ts: 100, text: '[Moost要約] summarize this'),
      line(sessionId: 's2', ts: 100, text: 'normal'),
    ].join('\n'));

    final entries = await reader.aggregatedEntries();
    expect(entries.map((e) => e.sessionId), ['s2']);
  });

  test('skips unparsable and incomplete lines', () async {
    await historyFile.writeAsString([
      'not json',
      '{"session_id":"s1","ts":100}', // text 欠落
      '',
      line(sessionId: 's2', ts: 100, text: 'ok'),
    ].join('\n'));

    final entries = await reader.aggregatedEntries();
    expect(entries.map((e) => e.sessionId), ['s2']);
  });
}
