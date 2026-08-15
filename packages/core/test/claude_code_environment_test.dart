import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('isClaudeCodeInternalEnvVar', () {
    test('matches known non-prefixed vars', () {
      expect(isClaudeCodeInternalEnvVar('CLAUDECODE'), isTrue);
      expect(isClaudeCodeInternalEnvVar('AI_AGENT'), isTrue);
    });

    test('matches any CLAUDE_-prefixed var, including unlisted ones', () {
      // CLAUDE_PID は事前の固定リストになかった実例（本文参照）。
      // プレフィックスマッチなら個別追加なしで拾えることを確認する
      expect(isClaudeCodeInternalEnvVar('CLAUDE_PID'), isTrue);
      expect(isClaudeCodeInternalEnvVar('CLAUDE_CODE_CHILD_SESSION'), isTrue);
      expect(isClaudeCodeInternalEnvVar('CLAUDE_SOME_FUTURE_VAR'), isTrue);
    });

    test('does not match unrelated vars', () {
      expect(isClaudeCodeInternalEnvVar('PATH'), isFalse);
      expect(isClaudeCodeInternalEnvVar('HOME'), isFalse);
      expect(isClaudeCodeInternalEnvVar('ANTHROPIC_API_KEY'), isFalse);
    });
  });

  group('withoutClaudeCodeInternalEnv', () {
    test('removes internal vars while keeping everything else', () {
      final filtered = withoutClaudeCodeInternalEnv({
        'PATH': '/usr/bin',
        'HOME': '/Users/x',
        'CLAUDE_CODE_CHILD_SESSION': '1',
        'CLAUDE_PID': '123',
        'AI_AGENT': 'claude-code',
        'CLAUDECODE': '1',
      });

      expect(filtered, {
        'PATH': '/usr/bin',
        'HOME': '/Users/x',
      });
    });
  });

  group('claudeCodeEnvUnsetPrefix', () {
    test('builds an env -u prefix covering every known var', () {
      final prefix = claudeCodeEnvUnsetPrefix();

      expect(prefix, startsWith('env '));
      expect(prefix, endsWith(' '));
      for (final name in knownClaudeCodeEnvVarNames) {
        expect(prefix, contains('-u $name'));
      }
    });
  });
}
