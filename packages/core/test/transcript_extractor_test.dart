import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory projectsDir;
  late TranscriptExtractor extractor;

  const sessionId = 'abc-session';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    projectsDir = Directory('${tempDir.path}/projects');
    extractor = TranscriptExtractor(projectsDir: projectsDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  String userLine(String text, {bool sidechain = false}) => jsonEncode({
        'type': 'user',
        'isSidechain': sidechain,
        'message': {'role': 'user', 'content': text},
      });

  String assistantLine(String text) => jsonEncode({
        'type': 'assistant',
        'isSidechain': false,
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      });

  Future<void> writeSession(List<String> lines) async {
    final dir = Directory('${projectsDir.path}/-Users-u-proj');
    await dir.create(recursive: true);
    await File('${dir.path}/$sessionId.jsonl')
        .writeAsString(lines.join('\n'));
  }

  test('returns null when session file is missing', () async {
    expect(await extractor.extract(sessionId), isNull);
  });

  test('extracts the last N rallies', () async {
    await writeSession([
      userLine('question 1'),
      assistantLine('answer 1'),
      userLine('question 2'),
      assistantLine('answer 2'),
      userLine('question 3'),
      assistantLine('answer 3'),
    ]);

    final transcript = await extractor.extract(sessionId, rallies: 2);
    expect(transcript, isNotNull);
    expect(transcript, isNot(contains('question 1')));
    expect(transcript, contains('User: question 2'));
    expect(transcript, contains('Assistant: answer 2'));
    expect(transcript, contains('User: question 3'));
    expect(transcript, contains('Assistant: answer 3'));
  });

  test('skips sidechain and non-message lines', () async {
    await writeSession([
      '{"type":"file-history-snapshot","snapshot":{}}',
      'broken line',
      userLine('sidechain q', sidechain: true),
      userLine('real question'),
      assistantLine('real answer'),
    ]);

    final transcript = await extractor.extract(sessionId, rallies: 5);
    expect(transcript, isNot(contains('sidechain q')));
    expect(transcript, contains('User: real question'));
    expect(transcript, contains('Assistant: real answer'));
  });

  test('joins multiple assistant text blocks in one rally', () async {
    await writeSession([
      userLine('q'),
      assistantLine('part 1'),
      assistantLine('part 2'),
    ]);

    final transcript = await extractor.extract(sessionId, rallies: 1);
    expect(transcript, contains('Assistant: part 1'));
    expect(transcript, contains('Assistant: part 2'));
  });

  test('returns null when there are no rallies', () async {
    await writeSession(['{"type":"noise"}']);
    expect(await extractor.extract(sessionId), isNull);
  });
}
