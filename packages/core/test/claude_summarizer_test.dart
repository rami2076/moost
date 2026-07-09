import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// フェイクの claude 実行ファイル（シェルスクリプト）で
/// サブプロセス処理を検証する。実際の claude は呼ばない。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> writeFakeClaude(String script) async {
    final file = File('${tempDir.path}/claude');
    await file.writeAsString('#!/bin/sh\n$script\n');
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  test('summarizeTranscript passes stdin and returns stdout', () async {
    // stdin をそのまま echo するフェイク: stdin が渡ることと EOF まで
    // 読み切れることの両方を検証する
    final path = await writeFakeClaude('cat -');
    final summarizer = ClaudeSummarizer(claudePath: path);

    final result = await summarizer.summarizeTranscript(
      'User: hello\nAssistant: world',
      workingDirectory: tempDir.path,
    );
    expect(result, 'User: hello\nAssistant: world');
  });

  test('large output does not deadlock the pipe buffer', () async {
    // 典型的なパイプバッファ（64KB）を超える出力を吐かせる
    final path = await writeFakeClaude(
      'i=0; while [ \$i -lt 3000 ]; do echo "0123456789012345678901234567890123456789"; i=\$((i+1)); done',
    );
    final summarizer = ClaudeSummarizer(claudePath: path);

    final result = await summarizer
        .summarizeTranscript('x', workingDirectory: tempDir.path)
        .timeout(const Duration(seconds: 30));
    expect(result.length, greaterThan(64 * 1024));
  });

  test('summarize prompt starts with the Moost marker', () async {
    // 引数をダンプするフェイクでマーカー付与を検証
    final path = await writeFakeClaude('echo "\$@"');
    final summarizer = ClaudeSummarizer(claudePath: path);

    final result = await summarizer.summarizeFullSession(
      sessionId: 'abc',
      workingDirectory: tempDir.path,
    );
    expect(result, contains(ClaudeSummarizer.marker));
    expect(result, contains('--resume abc'));
    expect(result, contains('--fork-session'));
    expect(result, contains('--model haiku'));
  });

  test('non-zero exit code throws SummarizeException with stderr', () async {
    final path = await writeFakeClaude('echo "boom" >&2; exit 7');
    final summarizer = ClaudeSummarizer(claudePath: path);

    await expectLater(
      summarizer.summarizeTranscript('x', workingDirectory: tempDir.path),
      throwsA(isA<SummarizeException>()
          .having((e) => e.message, 'message', contains('boom'))),
    );
  });

  test('large stdin to a process that never reads it does not crash',
      () async {
    // stdin を読まずに即終了するプロセス → broken pipe を握りつぶして
    // exitCode ベースのエラーになることを検証
    final path = await writeFakeClaude('exit 3');
    final summarizer = ClaudeSummarizer(claudePath: path);
    final bigInput = 'x' * (256 * 1024);

    await expectLater(
      summarizer
          .summarizeTranscript(bigInput, workingDirectory: tempDir.path)
          .timeout(const Duration(seconds: 30)),
      throwsA(isA<SummarizeException>()),
    );
  });

  test('missing executable throws SummarizeException', () async {
    final summarizer =
        ClaudeSummarizer(claudePath: '${tempDir.path}/no-such-claude');

    await expectLater(
      summarizer.summarizeTranscript('x', workingDirectory: tempDir.path),
      throwsA(isA<SummarizeException>()),
    );
  });
}
