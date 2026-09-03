import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// サンプルの pi JSONL を書く。
Future<File> writeSession(
  Directory sessionsRoot,
  String cwdSlug,
  String sessionId,
  String cwd, {
  String userText = 'こんにちは',
  int? timestampMillis,
}) async {
  final dir = Directory('${sessionsRoot.path}/$cwdSlug');
  await dir.create(recursive: true);
  final tsIso = DateTime.fromMillisecondsSinceEpoch(
    timestampMillis ?? DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String().replaceAll(':', '-').replaceAll('.', '-');

  final file = File(
    '${dir.path}/${tsIso}_$sessionId.jsonl',
  );
  final lines = <String, Object>{
    'type': 'session',
    'version': 2,
    'id': sessionId,
    'timestamp': DateTime.fromMillisecondsSinceEpoch(
      timestampMillis ?? DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String(),
    'cwd': cwd,
  };
  final content = <String>[
    jsonEncode(lines),
    jsonEncode({
      'type': 'message',
      'id': 'm1',
      'parentId': null,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        (timestampMillis ?? DateTime.now().millisecondsSinceEpoch) + 1000,
        isUtc: true,
      ).toIso8601String(),
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userText},
        ],
      },
    }),
    jsonEncode({
      'type': 'message',
      'id': 'm2',
      'parentId': 'm1',
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        (timestampMillis ?? DateTime.now().millisecondsSinceEpoch) + 2000,
        isUtc: true,
      ).toIso8601String(),
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': 'hmm'},
          {'type': 'text', 'text': '了解です'},  // アシスタント発言
        ],
      },
    }),
  ].join('\n');

  await file.writeAsString(content);
  return file;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pi_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<Directory> sessionsRoot() async {
    final dir = Directory('${tempDir.path}/.pi/agent/sessions');
    await dir.create(recursive: true);
    return dir;
  }

  group('PiSessionHistoryReader', () {
    test('reads header + last user prompt and sorts by updatedAt', () async {
      await writeSession(
        await sessionsRoot(),
        '--home-nyx-works-moost--',
        'aaaa',
        '/home/nyx/Documents/works/moost',
        userText: 'pi の会話ログを取得したい',
        timestampMillis: DateTime.utc(2026, 8, 29, 1).millisecondsSinceEpoch,
      );
      await writeSession(
        await sessionsRoot(),
        '--home-nyx-works-docs--',
        'bbbb',
        '/home/nyx/Documents/works/docs',
        userText: '別のセッション',
        timestampMillis: DateTime.utc(2026, 8, 29, 2).millisecondsSinceEpoch,
      );

      final reader = PiSessionHistoryReader(sessionsDir: await sessionsRoot());
      final sessions = await reader.recentSessions();

      expect(sessions, hasLength(2));
      // 新しい方が先
      expect(sessions.first.sessionId, 'bbbb');
      expect(sessions.first.projectPath, '/home/nyx/Documents/works/docs');
      expect(sessions.first.lastPrompt, '別のセッション');
      expect(sessions.last.sessionId, 'aaaa');
      expect(sessions.last.lastPrompt, 'pi の会話ログを取得したい');
    });

    test('ignores files without a session header and empty dirs', () async {
      final root = await sessionsRoot();
      final stray =
          File('${root.path}/--home-x--/broken.jsonl');
      await stray.parent.create(recursive: true);
      await stray.writeAsString('not json\n');
      final reader = PiSessionHistoryReader(sessionsDir: root);
      expect(await reader.recentSessions(), isEmpty);
    });

    test('respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await writeSession(
          await sessionsRoot(),
          'slug$i',
          'id$i',
          '/p/$i',
          userText: 'msg $i',
          timestampMillis:
              DateTime.utc(2026, 1, 1).millisecondsSinceEpoch + i * 60000,
        );
      }
      final reader = PiSessionHistoryReader(sessionsDir: await sessionsRoot());
      final sessions = await reader.recentSessions(limit: 2);
      expect(sessions, hasLength(2));
      expect(sessions.first.sessionId, 'id4');
    });
  });

  group('PiAdapter', () {
    test('resume command cds and calls pi --session', () {
      final adapter = PiAdapter();
      final command = adapter.buildResumeCommand(
        projectPath: '/a b/c',
        sessionId: '01aaaa-xyz',
      );
      expect(command, "cd '/a b/c' && pi --session '01aaaa-xyz'");
    });

    test('new session command starts pi in the directory', () {
      final adapter = PiAdapter();
      expect(
        adapter.buildNewSessionCommand(projectPath: '/work/moost'),
        "cd '/work/moost' && pi",
      );
    });

    test('recentSessions returns sessions from the directory', () async {
      final root = await sessionsRoot();
      await writeSession(
        root,
        '--moost--',
        'sess1',
        '/work/moost',
        userText: 'こんにちは pi',
        timestampMillis: DateTime.utc(2026, 3, 1).millisecondsSinceEpoch,
      );
      final adapter = PiAdapter(
        historyReader: PiSessionHistoryReader(sessionsDir: root),
        transcriptExtractor: PiTranscriptExtractor(sessionsDir: root),
      );
      final sessions = await adapter.recentSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.agentId, 'pi');
      expect(sessions.single.displayTitle, 'こんにちは pi');
    });
  });

  group('PiTranscriptExtractor', () {
    test('extracts recent messages as User/Assistant text', () async {
      final root = await sessionsRoot();
      await writeSession(
        root,
        '--moost--',
        'sess-extract',
        '/work/moost',
        userText: '最初の質問',
        timestampMillis: DateTime.utc(2026, 3, 1).millisecondsSinceEpoch,
      );
      final extractor = PiTranscriptExtractor(sessionsDir: root);
      final text = await extractor.extract(sessionId: 'sess-extract');
      expect(text, contains('User: 最初の質問'));
      expect(text, contains('Assistant: 了解です'));
    });

    test('full scope includes messages; recent limits to rallies', () async {
      // 直近 1 ラリー（=2 メッセージ）のみを含む検証は writeSession が
      // 2 メッセージしか書かないため、同じ結果になる。ここでは缩小
      // しない full を確認する
      final root = await sessionsRoot();
      await writeSession(
        root,
        '--m--',
        'sess-full',
        '/w',
        userText: 'A',
        timestampMillis: DateTime.utc(2026, 3, 1).millisecondsSinceEpoch,
      );
      final extractor = PiTranscriptExtractor(sessionsDir: root);
      expect(await extractor.extract(sessionId: 'sess-full', full: true),
          contains('Assistant: 了解です'));
    });

    test('empty result when the session file does not exist', () async {
      final extractor =
          PiTranscriptExtractor(sessionsDir: await sessionsRoot());
      final text = await extractor.extract(sessionId: 'no-such');
      expect(text, isEmpty);
    });
  });
}
