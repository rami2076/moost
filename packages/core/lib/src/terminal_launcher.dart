import 'dart:io';

/// 復帰先ターミナル。
enum TerminalApp {
  terminal('Terminal.app'),
  iterm2('iTerm2'),
  gnomeTerminal('gnome-terminal');

  final String settingValue;

  const TerminalApp(this.settingValue);

  /// 設定値 (文字列) から該当するターミナルへ。
  ///
  /// 未知の値（手書き編集・旧バージョン等）は現在の OS の既定
  /// （macOS なら Terminal.app / Linux なら gnome-terminal）へフォールバックする。
  static TerminalApp fromSetting(
    String value, {
    bool? isLinux,
  }) {
    for (final app in TerminalApp.values) {
      if (app.settingValue == value) {
        return app;
      }
    }
    return osDefault(isLinux: isLinux ?? Platform.isLinux);
  }

  /// 現在の OS の既定ターミナル。
  static TerminalApp osDefault({bool? isLinux}) {
    if (isLinux ?? Platform.isLinux) {
      return TerminalApp.gnomeTerminal;
    }
    return TerminalApp.terminal;
  }

  /// 保存された設定を現在の OS で実際に実行可能なターミナルへ正規化する。
  ///
  /// macOS 専用ターミナル（Terminal.app / iTerm2）が設定に残っていても
  /// Linux 上では存在しないため gnome-terminal に置き換える。
  static TerminalApp forPlatform(
    TerminalApp app, {
    bool? isLinux,
  }) {
    if (!(isLinux ?? Platform.isLinux)) {
      return app;
    }
    return switch (app) {
      TerminalApp.gnomeTerminal => TerminalApp.gnomeTerminal,
      TerminalApp.terminal || TerminalApp.iterm2 => TerminalApp.gnomeTerminal,
    };
  }
}

/// ターミナルを開いて復帰コマンドを実行する。
///
/// - macOS: osascript 経由で Terminal.app / iTerm2 を開く
/// - Linux: gnome-terminal（無ければ x-terminal-emulator）で新しい
///   ウィンドウを開き bash でコマンドを実行する
///
/// 復帰コマンドは POSIX シェル文法（`cd ... && claude --resume ...`）で
/// 組み立てられる（macOS の AppleScript 埋め込みや Linux の bash 実行に
/// 共通して使えるため）。
class TerminalLauncher {
  /// macOS: コマンド実行を差し替え可能にする（テスト用）。
  /// osascript（iTerm2）と /usr/bin/open（Terminal.app の .command 起動）の両方を受け止める。
  final Future<ProcessResult> Function(List<String> args) runMacosCommand;

  /// Linux: ターミナル起動コマンドの実行を差し替え可能にする（テスト用）。
  final Future<ProcessResult> Function(List<String> args) runLinuxCommand;

  /// テスト用にプラットフォーム分岐を固定できる。null なら実環境の判定を使う。
  final bool _isLinux;

  TerminalLauncher({
    Future<ProcessResult> Function(List<String> args)? runMacosCommand,
    Future<ProcessResult> Function(List<String> args)? runLinuxCommand,
    bool? isLinux,
  })  : runMacosCommand = runMacosCommand ??
            ((args) => Process.run(args.first, args.sublist(1))),
        runLinuxCommand = runLinuxCommand ??
            ((args) => Process.run(args.first, args.sublist(1))),
        _isLinux = isLinux ?? Platform.isLinux;

  Future<void> launch({
    required TerminalApp terminal,
    required String command,
  }) async {
    if (_isLinux) {
      await _launchLinux(TerminalApp.forPlatform(terminal, isLinux: _isLinux), command);
      return;
    }
    await _launchMacos(terminal, command);
  }

  /// Linux で新しいターミナルウィンドウを開き、[command] を bash で実行する。
  ///
  /// gnome-terminal が無ければ x-terminal-emulator（Debian/Ubuntu の
  /// update-alternatives エントリ）へフォールバックする。両方無ければ
  /// 明確なエラーを投げる。
  Future<void> _launchLinux(TerminalApp terminal, String command) async {
    final binary = await _findLinuxTerminal();
    if (binary == null) {
      throw const TerminalLaunchException(
        'no supported terminal found: install gnome-terminal or '
        'x-terminal-emulator',
      );
    }
    List<String> args;
    if (terminal == TerminalApp.gnomeTerminal) {
      // gnome-terminal は `--` の後に実行コマンドを続けられる。
      // -l でログインシェルとして起動し .profile/.bashrc 由来の PATH を
      // 拾わせる（GUI アプリから launch すると PATH が最小限になるため。
      // claude_path_resolver と共通の理屈）
      args = [binary, '--', 'bash', '-lc', command];
    } else {
      // x-terminal-emulator 等の汎用エントリは `-e` 形式のみ保証される
      args = [binary, '-e', 'bash', '-lc', command];
    }
    final result = await runLinuxCommand(args);
    if (result.exitCode != 0) {
      throw TerminalLaunchException(
        '${terminal.settingValue}: ${result.stderr}',
      );
    }
  }

  /// PATH から gnome-terminal を探し、無ければ x-terminal-emulator を返す。
  ///
  /// コマンド自体は存在しても起動に失敗する場合（DISPLAY なし等）は
  /// 実行時に exitCode != 0 で拾う。
  Future<String?> _findLinuxTerminal() async {
    for (final candidate in const ['gnome-terminal', 'x-terminal-emulator']) {
      final result = await runLinuxCommand(
        ['sh', '-c', r'command -v $1', '_', candidate],
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty && path != candidate) {
          return path;
        }
      }
    }
    return null;
  }

  Future<void> _launchMacos(
    TerminalApp terminal,
    String command,
  ) async {
    if (terminal == TerminalApp.terminal) {
      // Terminal.app は AppleScript (do script) ではなく .command ファイル + open で開く。
      // 署名なしアプリからの Apple Events は tccd への確認が 9 秒かかり、
      // UI がブロックされる要因になる（2026-10-02 実機計測済み）。
      // open は LaunchServices 経由で 0.2 秒程度（シェルからの実測 0.15s）。
      await _launchTerminalAppViaCommandFile(command);
      return;
    }
    final script = switch (terminal) {
      TerminalApp.iterm2 => _iterm2Script(command),
      // macOS 上で gnome-terminal が選ばれることはないが、
      // 万一のため Terminal.app 相当にフォールバックする
      TerminalApp.gnomeTerminal => _terminalScript(command),
      // 上の分岐で return 済み
      TerminalApp.terminal => _terminalScript(command),
    };
    final result = await runMacosCommand(['-e', script]);
    if (result.exitCode != 0) {
      throw TerminalLaunchException(
        '${terminal.settingValue}: ${result.stderr}',
      );
    }
  }

  /// .command 実行ファイルを一時ディレクトリに書き出し、open で Terminal.app を開く。
  /// Terminal.app は LaunchServices 経由で .command を新しいウィンドウで実行する
  /// （iTerm2 は .command を実行しないため iTerm2 では使えない）。
  Future<void> _launchTerminalAppViaCommandFile(String command) async {
    final file = File(
      '${Directory.systemTemp.path}/moost-'
      '${DateTime.now().microsecondsSinceEpoch}.command',
    );
    await file.writeAsString('#!/bin/zsh\n$command\n');
    await Process.run('chmod', ['+x', file.path]);
    final result = await runMacosCommand([
      '/usr/bin/open',
      '-a',
      'Terminal',
      file.path,
    ]);
    // open は即座に返る。ファイルは起動完了を妨げないよう 30 秒後に削除する。
    Future.delayed(const Duration(seconds: 30), () {
      try {
        file.deleteSync();
      } catch (_) {
        // 既に消えている etc. は無視
      }
    });
    if (result.exitCode != 0) {
      throw TerminalLaunchException(
        '${TerminalApp.terminal.settingValue}: ${result.stderr}',
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
    // iTerm2 の AppleScript アプリケーション名は "iTerm"（表示名は iTerm2）。
    // "iTerm2" で tell すると -2741 (syntax error) になる（2026-10-02 実機検証済み）。
    // iTerm2 は強制終了（kill）後でも次回起動時に前回のウィンドウを復元するため、
    // 常に create window すると「復元窓 + 新窓」で 2 窓になる（2026-10-03 実機検証済み）。
    // 復元完了前に (count of windows) を評価すると 0 になり 2 窓になるため、
    // ウィンドウが現れるまでポーリングで待ってから分岐する（最大 4.5 秒）。
    final escaped = _escape(command);
    return '''
tell application "iTerm"
  activate
  set attemptCount to 0
  repeat while (count of windows) = 0 and attemptCount < 15
    delay 0.3
    set attemptCount to attemptCount + 1
  end repeat
  if (count of windows) = 0 then
    set newWindow to (create window with default profile)
    tell current session of newWindow
      write text "$escaped"
    end tell
  else
    tell current window
      create tab with default profile
      tell current session
        write text "$escaped"
      end tell
    end tell
  end if
end tell''';
  }
}

class TerminalLaunchException implements Exception {
  final String message;

  const TerminalLaunchException(this.message);

  @override
  String toString() => 'TerminalLaunchException: $message';
}
