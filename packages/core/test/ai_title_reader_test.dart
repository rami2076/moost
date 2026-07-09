import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory projectsDir;
  late AiTitleReader reader;

  const sessionId = '77e31958-86fe-433e-b1dc-9d9059daa112';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    projectsDir = Directory('${tempDir.path}/projects');
    reader = AiTitleReader(projectsDir: projectsDir);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<File> writeSessionFile(String content,
      {String dirName = '-Users-u-proj'}) async {
    final dir = Directory('${projectsDir.path}/$dirName');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$sessionId.jsonl');
    await file.writeAsString(content);
    return file;
  }

  test('returns null when projects dir does not exist', () async {
    expect(await reader.latestAiTitle(sessionId), isNull);
  });

  test('returns null when session file is not found', () async {
    await Directory('${projectsDir.path}/-Users-u-proj')
        .create(recursive: true);
    expect(await reader.latestAiTitle(sessionId), isNull);
  });

  test('finds session file regardless of directory name encoding', () async {
    await writeSessionFile(
      '{"type":"ai-title","aiTitle":"タイトル","sessionId":"$sessionId"}\n',
      dirName: 'totally-unrelated-dir-name',
    );
    expect(await reader.latestAiTitle(sessionId), 'タイトル');
  });

  test('returns the latest ai-title when there are several', () async {
    await writeSessionFile([
      '{"type":"ai-title","aiTitle":"古いタイトル"}',
      '{"type":"user","message":{"content":"hi"}}',
      '{"type":"ai-title","aiTitle":"新しいタイトル"}',
      '{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}',
    ].join('\n'));
    expect(await reader.latestAiTitle(sessionId), '新しいタイトル');
  });

  test('reads only the tail window of a large file', () async {
    final reader = AiTitleReader(projectsDir: projectsDir, tailBytes: 1024);
    final padding =
        List.filled(200, '{"type":"noise","data":"0123456789"}').join('\n');
    await writeSessionFile([
      '{"type":"ai-title","aiTitle":"窓の外の古いタイトル"}',
      padding,
      '{"type":"ai-title","aiTitle":"末尾のタイトル"}',
    ].join('\n'));
    // 末尾 1KB の外にある古いタイトルは読まれず、窓内の最新が返る
    expect(await reader.latestAiTitle(sessionId), '末尾のタイトル');
  });

  test('skips lines that contain the keyword but are not valid', () async {
    await writeSessionFile([
      'not json but mentions "ai-title" here',
      '{"type":"other","note":"has \\"ai-title\\" text"}',
      '{"type":"ai-title","aiTitle":""}',
      '{"type":"ai-title","aiTitle":"有効なタイトル"}',
    ].join('\n'));
    expect(await reader.latestAiTitle(sessionId), '有効なタイトル');
  });
}
