/// spec/testdata の共通 Fixture を使った適合検証（フェーズ A、Issue #70）。
///
/// `spec/` は各プラットフォームの native 実装も同じ Fixture で検査する契約の正。
/// ここでは Dart リファレンス実装が契約を満たすことを示す。
library;

import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// Fixture はリポジトリ直下の spec/。テストはパッケージ直下をカレントとして走る。
const _specRelPath = '../../spec';

File _fixture(String name) => File('$_specRelPath/testdata/$name');

void main() {
  group('spec/schemas', () {
    test('全スキーマが JSON として読め title を持つ', () {
      for (final name in ['memos', 'settings', 'projects']) {
        final file = File('$_specRelPath/schemas/$name.schema.json');
        expect(file.existsSync(), isTrue, reason: name);
        final decoded = jsonDecode(file.readAsStringSync());
        expect(decoded, isA<Map<String, Object?>>());
        expect((decoded as Map)['title'], isNotEmpty);
      }
    });
  });

  group('memos.json（B1-B3）', () {
    test('memos_valid.json が全件読め、危険文字はそのまま保持される', () async {
      final memos = await MemoStore(_fixture('memos_valid.json')).load();
      expect(memos, hasLength(2));
      final dangerous = memos.singleWhere((m) => m.agent == 'codex');
      expect(dangerous.tags, contains('backtick `x`'));
      expect(dangerous.title, contains(r'$(whoami)'));
      expect(dangerous.body, contains('/dev/null'));
    });

    test('memos_corrupt_entry.json は壊れた 1 件だけスキップし全体は捨てない', () async {
      final memos = await MemoStore(_fixture('memos_corrupt_entry.json')).load();
      expect(memos, hasLength(1));
      expect(memos.single.sessionId, 'S-OK');
    });
  });

  group('parseTags（B5）', () {
    test('カンマ区切りから trim・空要素除去', () {
      expect(parseTags('a, b ,,c'), ['a', 'b', 'c']);
    });
  });

  group('settings.json（C1-C2）', () {
    test('型が違う項目のみデフォルトにフォールバックする', () async {
      final settings = await SettingsStore(_fixture('settings_bad_types.json')).load();
      expect(settings.terminalApp, 'Terminal.app');
      expect(settings.recentSessionLimit, 20);
      expect(settings.claudePath, '');
      expect(settings.summaryRallyCount, 1);
      expect(settings.copyAnimation, isTrue);
    });

    test('存在しないファイルはデフォルト設定を返す', () async {
      final settings = await SettingsStore(File('/nonexistent/moost-spec/settings.json')).load();
      expect(settings, const Settings());
    });
  });

  group('history.jsonl（E1-E5）', () {
    Future<List<RecentSession>> read() => SessionHistoryReader(
          historyFile: _fixture('history.jsonl'),
          agentId: 'claude-code',
          excludeMarker: '#MOOST-FORK#',
        ).recentSessions();

    test('壊れた行と空行をスキップし、sessionId ごとに最新を採用する', () async {
      final sessions = await read();
      expect(sessions.map((s) => s.sessionId).toSet(), {'S1', 'S2', 'S3'});

      final s1 = sessions.singleWhere((s) => s.sessionId == 'S1');
      expect(s1.agentId, 'claude-code');
      expect(s1.projectPath, '/work/alpha');
      expect(s1.lastPrompt, 'second prompt');
      expect(s1.updatedAt.millisecondsSinceEpoch, 2000);

      final s3 = sessions.singleWhere((s) => s.sessionId == 'S3');
      expect(s3.lastPrompt, 'third prompt');
      expect(s3.updatedAt.millisecondsSinceEpoch, 4000);
    });

    test('全プロンプトがマーカーのセッションは除外し、混在セッションはマーカー行のみ除外する（E3）', () async {
      final sessions = await read();
      // S4 はマーカー行のみのセッション → 一覧に出ない
      expect(sessions.map((s) => s.sessionId), isNot(contains('S4')));
      // S2 はマーカー行と通常行の混在 → 通常側の最新のみが残る
      final s2 = sessions.singleWhere((s) => s.sessionId == 'S2');
      expect(s2.lastPrompt, 'normal prompt');
      expect(s2.updatedAt.millisecondsSinceEpoch, 1500);
    });

    test('ai-title 無の表題フォールバック（F1）', () async {
      final sessions = await read();
      final s1 = sessions.singleWhere((s) => s.sessionId == 'S1');
      expect(s1.aiTitle, isNull);
      expect(s1.displayTitle, 'second prompt');
    });
  });
}
