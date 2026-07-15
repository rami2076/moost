import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// フェイクの codex 実行ファイル（シェルスクリプト）で
/// サブプロセス処理を検証する。実際の codex は呼ばない。
///
/// codex exec は結果を `--output-last-message <FILE>` に書くため、
/// フェイクも引数から出力先を拾ってそこへ書く。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// `--output-last-message` の次の引数を `$out` に入れた状態で
  /// [script] を実行するフェイク codex を作る。
  Future<String> writeFakeCodex(String script) async {
    final file = File('${tempDir.path}/codex');
    await file.writeAsString('''
#!/bin/sh
out=""
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--output-last-message" ]; then out="\$a"; fi
  prev="\$a"
done
$script
''');
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  test('summarizeTranscript passes stdin and reads the output file',
      () async {
    final path = await writeFakeCodex('cat - > "\$out"');
    final summarizer = CodexSummarizer(codexPath: path);

    final result = await summarizer.summarizeTranscript(
      'User: hello\nAssistant: world',
      workingDirectory: tempDir.path,
    );
    expect(result, 'User: hello\nAssistant: world');
  });

  test('transcript summary runs ephemeral exec with the marker', () async {
    final path = await writeFakeCodex('echo "\$@" > "\$out"');
    final summarizer = CodexSummarizer(codexPath: path);

    final result = await summarizer.summarizeTranscript(
      'x',
      workingDirectory: tempDir.path,
    );
    expect(result, startsWith('exec '));
    expect(result, contains('--ephemeral'));
    expect(result, contains('--skip-git-repo-check'));
    expect(result, contains('--sandbox read-only'));
    expect(result, contains(CodexSummarizer.marker));
  });

  test('full summary resumes the session ephemerally', () async {
    final path = await writeFakeCodex('echo "\$@" > "\$out"');
    final summarizer = CodexSummarizer(codexPath: path);

    final result = await summarizer.summarizeFullSession(
      sessionId: 'abc',
      workingDirectory: tempDir.path,
    );
    expect(result, startsWith('exec resume abc'));
    expect(result, contains('--ephemeral'));
    expect(result, contains(CodexSummarizer.marker));
  });

  test('non-zero exit code throws SummarizeException with stderr', () async {
    final path = await writeFakeCodex('echo "boom" >&2; exit 7');
    final summarizer = CodexSummarizer(codexPath: path);

    await expectLater(
      summarizer.summarizeTranscript('x', workingDirectory: tempDir.path),
      throwsA(isA<SummarizeException>()
          .having((e) => e.message, 'message', contains('boom'))),
    );
  });

  test('missing output file throws SummarizeException', () async {
    // 正常終了したのに結果ファイルを書かないフェイク
    final path = await writeFakeCodex('exit 0');
    final summarizer = CodexSummarizer(codexPath: path);

    await expectLater(
      summarizer.summarizeTranscript('x', workingDirectory: tempDir.path),
      throwsA(isA<SummarizeException>()),
    );
  });

  test('missing executable throws SummarizeException', () async {
    final summarizer =
        CodexSummarizer(codexPath: '${tempDir.path}/no-such-codex');

    await expectLater(
      summarizer.summarizeTranscript('x', workingDirectory: tempDir.path),
      throwsA(isA<SummarizeException>()),
    );
  });
}
