import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalApp.fromSetting', () {
    test('maps known values', () {
      expect(TerminalApp.fromSetting('Terminal.app'), TerminalApp.terminal);
      expect(TerminalApp.fromSetting('iTerm2'), TerminalApp.iterm2);
    });

    test('falls back to Terminal.app for unknown values', () {
      expect(TerminalApp.fromSetting('Alacritty'), TerminalApp.terminal);
    });
  });

  group('TerminalLauncher', () {
    late List<List<String>> calls;
    late TerminalLauncher launcher;

    void arrange({int exitCode = 0, String stderr = ''}) {
      calls = [];
      launcher = TerminalLauncher(runOsascript: (args) async {
        calls.add(args);
        return ProcessResult(0, exitCode, '', stderr);
      });
    }

    test('Terminal.app: uses do script with the command', () async {
      arrange();
      await launcher.launch(
        terminal: TerminalApp.terminal,
        command: 'cd /tmp && claude --resume abc',
      );
      final script = calls.single[1];
      expect(script, contains('tell application "Terminal"'));
      expect(script, contains('do script'));
      expect(script, contains('cd /tmp && claude --resume abc'));
    });

    test('iTerm2: opens a new window and writes text', () async {
      arrange();
      await launcher.launch(
        terminal: TerminalApp.iterm2,
        command: 'echo hi',
      );
      final script = calls.single[1];
      expect(script, contains('tell application "iTerm2"'));
      expect(script, contains('create window with default profile'));
      expect(script, contains('write text'));
    });

    test('escapes quotes and backslashes for AppleScript', () async {
      arrange();
      await launcher.launch(
        terminal: TerminalApp.terminal,
        command: r'cd "/a b" && x\y',
      );
      final script = calls.single[1];
      // " は \" に、\ は \\ にエスケープされる
      expect(script, contains(r'\"/a b\"'));
      expect(script, contains(r'x\\y'));
    });

    test('throws on non-zero exit code', () async {
      arrange(exitCode: 1, stderr: 'boom');
      await expectLater(
        launcher.launch(
          terminal: TerminalApp.terminal,
          command: 'x',
        ),
        throwsA(isA<TerminalLaunchException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });
}
