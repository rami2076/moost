import 'dart:convert';
import 'dart:io';

import '../summarize_exception.dart';

/// `claude -p` によるセッション要約の実行。
///
/// - モデルは haiku 固定（requirements.md 3.6）
/// - 全体要約のフォークセッションが一覧に混ざらないよう、
///   プロンプト先頭にマーカーを入れる（design.md 5 章）
/// - サブプロセスの stdout/stderr は終了待ちの前に EOF まで読み切る
///   （パイプバッファ詰まりでデッドロックするため。design.md 7 章ハマりどころ 2）
class ClaudeSummarizer {
  /// 要約用フォークセッションの除外マーカー。
  static const marker = '[Moost要約]';

  static const _model = 'haiku';

  final String claudePath;

  ClaudeSummarizer({required this.claudePath});

  /// 抜粋テキストを stdin で渡して要約する（直近要約）。
  Future<String> summarizeTranscript(
    String transcript, {
    required String workingDirectory,
  }) {
    return _run(
      arguments: [
        '-p',
        '--model',
        _model,
        '$marker 以下は AI コーディングエージェントとの会話の抜粋です。'
            '作業内容と現在の状況を簡潔に要約してください。',
      ],
      workingDirectory: workingDirectory,
      stdinText: transcript,
    );
  }

  /// セッションを fork して全体を要約する（全体要約）。
  Future<String> summarizeFullSession({
    required String sessionId,
    required String workingDirectory,
  }) {
    return _run(
      arguments: [
        '-p',
        '--resume',
        sessionId,
        '--fork-session',
        '--model',
        _model,
        '$marker このセッションの作業内容と現在の状況を簡潔に要約してください。',
      ],
      workingDirectory: workingDirectory,
    );
  }

  Future<String> _run({
    required List<String> arguments,
    required String workingDirectory,
    String? stdinText,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        claudePath,
        arguments,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throw SummarizeException('failed to start claude: ${e.message}');
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
      throw SummarizeException('claude exited with $exitCode: $detail');
    }
    return stdout.trim();
  }
}
