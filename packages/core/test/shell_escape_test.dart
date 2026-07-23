import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('shellEscape', () {
    test('wraps plain string in single quotes', () {
      expect(shellEscape('/Users/foo/project'), "'/Users/foo/project'");
    });

    test('escapes backquotes literally', () {
      // バッククォート入りパスの必須テスト（design.md 7 章ハマりどころ 4）
      expect(shellEscape(r'/tmp/we`ird'), r"'/tmp/we`ird'");
    });

    test('escapes single quotes', () {
      expect(shellEscape("it's"), r"'it'\''s'");
    });

    test('escapes dollar and spaces', () {
      expect(shellEscape(r'/tmp/$HOME dir'), r"'/tmp/$HOME dir'");
    });
  });

  group('buildResumeCommand (via ClaudeCodeAdapter)', () {
    final adapter = ClaudeCodeAdapter(claudeHome: '/nonexistent');

    test('builds cd && claude --resume', () {
      final command = adapter.buildResumeCommand(
        projectPath: '/Users/foo/project',
        sessionId: 'abc-123',
      );
      expect(
        command,
        "cd '/Users/foo/project' && claude --resume 'abc-123'",
      );
    });

    test('keeps backquoted path intact inside quotes', () {
      final command = adapter.buildResumeCommand(
        projectPath: '/tmp/we`ird path',
        sessionId: 'abc',
      );
      expect(command, contains("'/tmp/we`ird path'"));
    });
  });

  group('buildNewSessionCommand (via ClaudeCodeAdapter)', () {
    final adapter = ClaudeCodeAdapter(claudeHome: '/nonexistent');

    test('builds cd && claude without --resume', () {
      final command =
          adapter.buildNewSessionCommand(projectPath: '/Users/foo/project');
      expect(command, "cd '/Users/foo/project' && claude");
    });

    test('keeps backquoted path intact inside quotes', () {
      final command =
          adapter.buildNewSessionCommand(projectPath: '/tmp/we`ird path');
      expect(command, contains("'/tmp/we`ird path'"));
    });
  });
}
