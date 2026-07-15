import 'dart:convert';
import 'dart:io';

import '../summarize_exception.dart';

/// `codex exec` によるセッション要約の実行。
///
/// - `--ephemeral` でセッションを永続化しない（rollout も history も残らず、
///   Claude の `--fork-session` に相当する分離になる）
/// - 念のためプロンプト先頭にマーカーを入れる（万一 history に記録される
///   モードで動いても一覧から除外できるように。design.md 5 章と同じ発想）
/// - codex exec の stdout は進捗ログを含むため、結果は
///   `--output-last-message` で書かせたファイルから読む
/// - サブプロセスの stdout/stderr は終了待ちの前に EOF まで読み切る
///   （パイプバッファ詰まりでデッドロックするため。design.md 7 章ハマりどころ 2）
class CodexSummarizer {
  /// 要約実行の除外マーカー（ClaudeSummarizer.marker と同じ文字列）。
  static const marker = '[Moost要約]';

  final String codexPath;

  CodexSummarizer({required this.codexPath});

  /// 抜粋テキストを stdin で渡して要約する（直近要約）。
  ///
  /// codex exec はプロンプト引数がある状態で stdin をパイプすると
  /// `<stdin>` ブロックとして追記する仕様を使う。
  Future<String> summarizeTranscript(
    String transcript, {
    required String workingDirectory,
  }) {
    return _run(
      buildArguments: (outputFile) => [
        'exec',
        '--ephemeral',
        '--skip-git-repo-check',
        '--sandbox',
        'read-only',
        '--output-last-message',
        outputFile,
        '$marker 以下は AI コーディングエージェントとの会話の抜粋です。'
            '作業内容と現在の状況を簡潔に要約してください。',
      ],
      workingDirectory: workingDirectory,
      stdinText: transcript,
    );
  }

  /// セッションを ephemeral で resume して全体を要約する（全体要約）。
  Future<String> summarizeFullSession({
    required String sessionId,
    required String workingDirectory,
  }) {
    return _run(
      buildArguments: (outputFile) => [
        'exec',
        'resume',
        sessionId,
        '--ephemeral',
        '--skip-git-repo-check',
        '--output-last-message',
        outputFile,
        '$marker このセッションの作業内容と現在の状況を簡潔に要約してください。',
      ],
      workingDirectory: workingDirectory,
    );
  }

  Future<String> _run({
    required List<String> Function(String outputFile) buildArguments,
    required String workingDirectory,
    String? stdinText,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('moost_codex_');
    final outputFile = File('${tempDir.path}/last_message.txt');
    try {
      final Process process;
      try {
        process = await Process.start(
          codexPath,
          buildArguments(outputFile.path),
          workingDirectory: workingDirectory,
        );
      } on ProcessException catch (e) {
        throw SummarizeException('failed to start codex: ${e.message}');
      }

      // プロセスが stdin を読まずに終了した場合の broken pipe を許容する
      // （エラーは exitCode / stderr 側で検知する）
      try {
        if (stdinText != null) {
          process.stdin.write(stdinText);
        }
        await process.stdin.close();
        await process.stdin.done;
      } on Object {
        // ignore: broken pipe when the process exits early
      }

      // exitCode を待つ前に両ストリームを EOF まで読み切る
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        final detail = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
        throw SummarizeException('codex exited with $exitCode: $detail');
      }

      final String result;
      try {
        result = (await outputFile.readAsString()).trim();
      } on FileSystemException {
        throw SummarizeException('codex did not produce a summary');
      }
      if (result.isEmpty) {
        throw SummarizeException('codex returned an empty summary');
      }
      return result;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // ignore: temp cleanup failure is not worth surfacing
      }
    }
  }
}
