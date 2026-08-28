import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalApp.fromSetting', () {
    test('maps known values', () {
      expect(TerminalApp.fromSetting('Terminal.app'), TerminalApp.terminal);
      expect(TerminalApp.fromSetting('iTerm2'), TerminalApp.iterm2);
      expect(
        TerminalApp.fromSetting('gnome-terminal'),
        TerminalApp.gnomeTerminal,
      );
    });

    test('falls back to OS default for unknown values', () {
      expect(
        TerminalApp.fromSetting('Alacritty', isLinux: false),
        TerminalApp.terminal,
      );
      expect(
        TerminalApp.fromSetting('Alacritty', isLinux: true),
        TerminalApp.gnomeTerminal,
      );
    });
  });

  group('TerminalApp.forPlatform', () {
    test('macOS keeps macOS-only terminals', () {
      expect(
        TerminalApp.forPlatform(TerminalApp.terminal, isLinux: false),
        TerminalApp.terminal,
      );
      expect(
        TerminalApp.forPlatform(TerminalApp.iterm2, isLinux: false),
        TerminalApp.iterm2,
      );
    });

    test('Linux normalizes macOS-only terminals to gnome-terminal', () {
      for (final app in TerminalApp.values) {
        expect(
          TerminalApp.forPlatform(app, isLinux: true),
          TerminalApp.gnomeTerminal,
        );
      }
    });
  });

  group('TerminalLauncher (macOS branch)', () {
    late List<List<String>> calls;
    late TerminalLauncher launcher;

    void arrange({int exitCode = 0, String stderr = ''}) {
      calls = [];
      launcher = TerminalLauncher(
        isLinux: false,
        runOsascript: (args) async {
          calls.add(args);
          return ProcessResult(0, exitCode, '', stderr);
        },
      );
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

  group('TerminalLauncher (Linux branch)', () {
    late List<List<String>> calls;
    late TerminalLauncher launcher;

    /// 端末検索 (`command -v gnome-terminal`) は成功し、その後の起動だけを
    /// 記録・制御する。デフォルトでは gnome-terminal が見つかる前提にする。
    void arrange({int exitCode = 0, String stderr = ''}) {
      calls = [];
      launcher = TerminalLauncher(
        isLinux: true,
        runLinuxCommand: (args) async {
          calls.add(args);
          final probe = args[0] == 'sh' && args.length == 5;
          if (probe) {
            // `sh -c 'command -v $1' _ gnome-terminal` の成功を再現
            return ProcessResult(0, 0, '/usr/bin/${args[4]}', '');
          }
          return ProcessResult(0, exitCode, '', stderr);
        },
      );
    }

    test('gnome-terminal: runs the command via bash login shell', () async {
      arrange();
      await launcher.launch(
        terminal: TerminalApp.gnomeTerminal,
        command: 'cd /tmp && claude --resume abc',
      );
      final launchArgs = calls.last;
      expect(launchArgs.first, contains('gnome-terminal'));
      // gnome-terminal -- bash -lc '...' の形で起動する
      expect(launchArgs, contains('--'));
      expect(launchArgs, contains('bash'));
      expect(launchArgs, anyElement(contains('-l')));
      expect(launchArgs.last, 'cd /tmp && claude --resume abc');
    });

    test('macOS-only terminal value is normalized on Linux', () async {
      arrange();
      await launcher.launch(
        terminal: TerminalApp.terminal, // settings に残った macOS 値
        command: 'echo hi',
      );
      expect(calls.last.first, contains('gnome-terminal'));
    });

    test('falls back to x-terminal-emulator when gnome-terminal is absent',
        () async {
      calls = [];
      launcher = TerminalLauncher(
        isLinux: true,
        runLinuxCommand: (args) async {
          calls.add(args);
          final probe = args[0] == 'sh' && args.length == 5;
          if (probe) {
            final cmd = args[4];
            if (cmd == 'gnome-terminal') {
              return ProcessResult(1, 1, '', 'not found');
            }
            return ProcessResult(0, 0, '/usr/bin/$cmd', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      await launcher.launch(
        terminal: TerminalApp.gnomeTerminal,
        command: 'echo hi',
      );
      expect(calls.last, anyElement(contains('x-terminal-emulator')));
    });

    test('throws when no terminal is found', () async {
      launcher = TerminalLauncher(
        isLinux: true,
        runLinuxCommand: (args) async {
          return ProcessResult(1, 1, '', 'not found');
        },
      );
      await expectLater(
        launcher.launch(
          terminal: TerminalApp.gnomeTerminal,
          command: 'echo hi',
        ),
        throwsA(isA<TerminalLaunchException>().having(
          (e) => e.message,
          'message',
          contains('no supported terminal'),
        )),
      );
    });

    test('throws on non-zero exit code', () async {
      arrange(exitCode: 1, stderr: 'boom');
      await expectLater(
        launcher.launch(
          terminal: TerminalApp.gnomeTerminal,
          command: 'x',
        ),
        throwsA(isA<TerminalLaunchException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });
}
