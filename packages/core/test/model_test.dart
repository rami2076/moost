import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  group('RecentSession.displayTitle', () {
    RecentSession build({String? aiTitle, String lastPrompt = 'prompt'}) {
      return RecentSession(
        sessionId: 'id',
        projectPath: '/p',
        lastPrompt: lastPrompt,
        updatedAt: DateTime.utc(2026),
        aiTitle: aiTitle,
      );
    }

    test('prefers ai-title when present', () {
      expect(build(aiTitle: 'AI タイトル').displayTitle, 'AI タイトル');
    });

    test('falls back to lastPrompt when ai-title is null or empty', () {
      expect(build(aiTitle: null).displayTitle, 'prompt');
      expect(build(aiTitle: '').displayTitle, 'prompt');
    });

    test('truncates fallback to 50 characters', () {
      final long = 'あ' * 80;
      final title = build(lastPrompt: long).displayTitle;
      expect(title.length, 50);
      expect(title, 'あ' * 50);
    });
  });

  group('parseTags', () {
    test('splits, trims and drops empty elements', () {
      expect(parseTags(' peko, 調査 ,,foo '), ['peko', '調査', 'foo']);
    });

    test('returns empty list for empty input', () {
      expect(parseTags(''), isEmpty);
      expect(parseTags(' , , '), isEmpty);
    });
  });

  group('generateUuidV4', () {
    test('has RFC 4122 v4 format and is unique', () {
      final uuid = generateUuidV4();
      expect(
        uuid,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      final many = {for (var i = 0; i < 1000; i++) generateUuidV4()};
      expect(many, hasLength(1000));
    });
  });
}
