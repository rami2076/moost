import 'dart:io';

/// OS のフォルダ選択ダイアログを開く（macOS。osascript 経由）。
///
/// TerminalLauncher と同じ方式（追加の pub パッケージなしで AppleScript の
/// `choose folder` を呼ぶ）。ダイアログは独立プロセスなので、常駐ポップオーバー
/// を閉じてしまう心配はない。
class FolderPicker {
  /// osascript 実行を差し替え可能にする（テスト用）。
  final Future<ProcessResult> Function(List<String> args) runOsascript;

  FolderPicker({
    Future<ProcessResult> Function(List<String> args)? runOsascript,
  }) : runOsascript =
            runOsascript ?? ((args) => Process.run('osascript', args));

  /// 選ばれたディレクトリの絶対パスを返す。ユーザーがキャンセルしたら null。
  Future<String?> pick() async {
    final result =
        await runOsascript(['-e', 'POSIX path of (choose folder)']);
    if (result.exitCode != 0) {
      // ユーザーによるキャンセルもここに入る（osascript が非 0 で終了する）
      return null;
    }
    final path = (result.stdout as String).trim();
    if (path.isEmpty) {
      return null;
    }
    // AppleScript の POSIX path はディレクトリ末尾に "/" を付けて返す
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}
