import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudePathResolver.resolve', () {
    test('returns the manual override, expanding a leading ~', () async {
      final resolver = ClaudePathResolver(home: '/Users/x');

      expect(await resolver.resolve(override: '~/bin/claude'),
          '/Users/x/bin/claude');
    });
  });

  group('ClaudePathResolver login-shell fallback (Issue #53)', () {
    // 既知パスの実在確認を常に false にし、実マシンにたまたま
    // /opt/homebrew/bin/claude 等が存在してもフォールバックまで
    // 確実に到達させる
    ClaudePathResolver resolverWith(
      Future<ProcessResult> Function(List<String> args) runZsh,
    ) =>
        ClaudePathResolver(
          home: '/nonexistent',
          runZsh: runZsh,
          fileExists: (path) async => false,
        );

    test('uses -lic (not -lc) so nvm/pyenv/asdf-style PATH via .zshrc is '
        'resolvable', () async {
      List<String>? capturedArgs;
      final resolver = resolverWith((args) async {
        capturedArgs = args;
        return ProcessResult(0, 0, '/Users/x/.local/bin/claude\n', '');
      });

      await resolver.resolve();

      expect(capturedArgs, ['-lic', 'command -v claude']);
    });

    test('takes only the last line when .zshrc pollutes stdout', () async {
      // -i を付けると .zshrc 自体が実行され、その中の echo 等の出力が
      // 標準出力に混ざることがある（実機で確認した実例に近い形）
      final resolver = resolverWith(
        (args) async => ProcessResult(
          0,
          0,
          'Restored session: 2026年8月15日 土曜日 11時52分02秒 JST\n'
              '/Users/x/.local/bin/claude\n',
          '',
        ),
      );

      expect(await resolver.resolve(), '/Users/x/.local/bin/claude');
    });

    test('returns null when the shell exits non-zero (not found)', () async {
      final resolver =
          resolverWith((args) async => ProcessResult(0, 1, '', 'not found'));

      expect(await resolver.resolve(), isNull);
    });

    test('returns null when stdout is empty after trimming', () async {
      final resolver =
          resolverWith((args) async => ProcessResult(0, 0, '\n', ''));

      expect(await resolver.resolve(), isNull);
    });
  });
}
