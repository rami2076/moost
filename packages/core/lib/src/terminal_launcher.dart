import 'dart:io';

/// 復帰先ターミナル。
enum TerminalApp {
  terminal('Terminal.app'),
  iterm2('iTerm2');

  final String settingValue;

  const TerminalApp(this.settingValue);

  static TerminalApp fromSetting(String value) {
    return TerminalApp.values.firstWhere(
      (t) => t.settingValue == value,
      orElse: () => TerminalApp.terminal,
    );
  }
}

/// ターミナルを開いて復帰コマンドを実行する（macOS。osascript 経由）。
///
/// 別ウィンドウ（Terminal / iTerm2）を開くのは常駐ポップオーバー特有の
/// 「ダイアログを出すと閉じる」制約（design.md 7 章ハマりどころ 5）とは別で、
/// 独立プロセスなので問題ない。
class TerminalLauncher {
  /// osascript 実行を差し替え可能にする（テスト用）。
  final Future<ProcessResult> Function(List<String> args) runOsascript;

  TerminalLauncher({
    Future<ProcessResult> Function(List<String> args)? runOsascript,
  }) : runOsascript = runOsascript ??
            ((args) => Process.run('osascript', args));

  Future<void> launch({
    required TerminalApp terminal,
    required String command,
  }) async {
    final script = switch (terminal) {
      TerminalApp.terminal => _terminalScript(command),
      TerminalApp.iterm2 => _iterm2Script(command),
    };
    final result = await runOsascript(['-e', script]);
    if (result.exitCode != 0) {
      throw TerminalLaunchException(
        '${terminal.settingValue}: ${result.stderr}',
      );
    }
  }

  /// AppleScript 文字列リテラル用にエスケープする（" と \ をエスケープ）。
  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  String _terminalScript(String command) {
    final escaped = _escape(command);
    return '''
tell application "Terminal"
  activate
  do script "$escaped"
end tell''';
  }

  String _iterm2Script(String command) {
    final escaped = _escape(command);
    return '''
tell application "iTerm2"
  activate
  set newWindow to (create window with default profile)
  tell current session of newWindow
    write text "$escaped"
  end tell
end tell''';
  }
}

class TerminalLaunchException implements Exception {
  final String message;

  const TerminalLaunchException(this.message);

  @override
  String toString() => 'TerminalLaunchException: $message';
}
