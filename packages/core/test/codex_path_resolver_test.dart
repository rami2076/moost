import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// テスト実行環境（＝ resolver の実環境）で使われるであろうシェル引数を返す。
/// CI は Linux ランナーで動くため、ここがプラットフォーム依存なのは
/// テストの実行環境と同一判定になることの裏返し。
List<String> shellProbeArgs(String binary) => Platform.isLinux
    ? ['-ic', 'command -v $binary']
    : ['-lic', 'command -v $binary'];

void main() {
  group('CodexPathResolver.resolve', () {
    test('returns the manual override, expanding a leading ~', () async {
      final resolver = CodexPathResolver(home: '/Users/x');

      expect(await resolver.resolve(override: '~/bin/codex'),
          '/Users/x/bin/codex');
    });
  });

  group('CodexPathResolver login-shell fallback (Issue #53)', () {
    // 既知パスの実在確認を常に false にし、実マシンにたまたま
    // /opt/homebrew/bin/codex 等が存在してもフォールバックまで
    // 確実に到達させる
    CodexPathResolver resolverWith(
      Future<ProcessResult> Function(List<String> args) runZsh,
    ) =>
        CodexPathResolver(
          home: '/nonexistent',
          runZsh: runZsh,
          fileExists: (path) async => false,
        );

    test('uses -lic (not -lc) so nvm/pyenv/asdf-style PATH via .zshrc is '
        'resolvable', () async {
      List<String>? capturedArgs;
      final resolver = resolverWith((args) async {
        capturedArgs = args;
        return ProcessResult(0, 0, '/Users/x/.local/bin/codex\n', '');
      });

      await resolver.resolve();

      expect(capturedArgs, shellProbeArgs('codex'));
    });

    test('takes only the last line when .zshrc pollutes stdout', () async {
      final resolver = resolverWith(
        (args) async => ProcessResult(
          0,
          0,
          'Restored session: 2026年8月15日 土曜日 11時52分02秒 JST\n'
              '/Users/x/.local/bin/codex\n',
          '',
        ),
      );

      expect(await resolver.resolve(), '/Users/x/.local/bin/codex');
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
