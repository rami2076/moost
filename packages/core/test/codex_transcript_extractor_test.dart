import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory sessionsDir;
  late CodexTranscriptExtractor extractor;

  const uuid = '019dd8a1-a10c-7ef0-867e-3873d724ec84';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    sessionsDir = Directory('${tempDir.path}/sessions');
    extractor = CodexTranscriptExtractor(
      rolloutReader: CodexRolloutReader(sessionsDir: sessionsDir),
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Map<String, Object?> userMessage(String text) => {
        'timestamp': 't',
        'type': 'response_item',
        'payload': {
          'type': 'message',
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': text},
          ],
        },
      };

  Map<String, Object?> assistantMessage(String text) => {
        'timestamp': 't',
        'type': 'response_item',
        'payload': {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': text},
          ],
        },
      };

  Future<void> writeRollout(List<Object> lines) async {
    final dir = Directory('${sessionsDir.path}/2026/04/29');
    await dir.create(recursive: true);
    await File('${dir.path}/rollout-2026-04-29T18-46-04-$uuid.jsonl')
        .writeAsString(lines.map(jsonEncode).join('\n'));
  }

  test('returns null when the rollout file is missing', () async {
    expect(await extractor.extract(uuid), isNull);
  });

  test('extracts the last rally by default', () async {
    await writeRollout([
      userMessage('first question'),
      assistantMessage('first answer'),
      userMessage('second question'),
      assistantMessage('second answer'),
    ]);

    final transcript = await extractor.extract(uuid);
    expect(transcript, 'User: second question\nAssistant: second answer');
  });

  test('extracts multiple rallies in order', () async {
    await writeRollout([
      userMessage('q1'),
      assistantMessage('a1'),
      userMessage('q2'),
      assistantMessage('a2'),
    ]);

    final transcript = await extractor.extract(uuid, rallies: 2);
    expect(
      transcript,
      'User: q1\nAssistant: a1\n\nUser: q2\nAssistant: a2',
    );
  });

  test('skips system-context user messages', () async {
    await writeRollout([
      userMessage('<environment_context>cwd: /p</environment_context>'),
      userMessage('<user_instructions>rules</user_instructions>'),
      userMessage('real question'),
      assistantMessage('answer'),
    ]);

    final transcript = await extractor.extract(uuid, rallies: 5);
    expect(transcript, 'User: real question\nAssistant: answer');
  });

  test('ignores event_msg and non-message lines', () async {
    final dir = Directory('${sessionsDir.path}/2026/04/29');
    await dir.create(recursive: true);
    await File('${dir.path}/rollout-2026-04-29T18-46-04-$uuid.jsonl')
        .writeAsString([
      jsonEncode({
        'type': 'event_msg',
        'payload': {'type': 'agent_message', 'message': 'not this'},
      }),
      'broken line',
      jsonEncode(userMessage('q')),
      jsonEncode(assistantMessage('a')),
    ].join('\n'));

    final transcript = await extractor.extract(uuid);
    expect(transcript, 'User: q\nAssistant: a');
  });
}
