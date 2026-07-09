import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/main.dart';

/// runAsync の中で実 I/O の完了を待ちながらフレームを進める。
///
/// I/O が連鎖する操作（保存 → 画面遷移 → 再読込）は「実時間待ち + pump」を
/// 複数サイクル回さないと最後の FutureBuilder までデータが届かない。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump();
  }
}

void main() {
  testWidgets('renders session list tab with empty stores', (tester) async {
    // FakeAsync ゾーン（runAsync の外）では非同期 I/O の Future が完了しない
    // ため、テンポラリディレクトリ操作は同期 API を使う
    final tempDir = Directory.systemTemp.createTempSync('moost_widget_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    // 実ファイル I/O を伴う Future は FakeAsync では完了しないため、
    // テスト全体を runAsync 内で実行し、pump を明示的に打つ
    // （スピナーのアニメーションがあるため pumpAndSettle は使えない）
    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        // 存在しないディレクトリを指す adapter → 空一覧になる
        adapter: ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude'),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      // 空状態の文言が出る（英語ロケールがデフォルト）
      expect(find.text('No sessions found'), findsOneWidget);

      // メモタブへ切替
      await tester.tap(find.text('Memos'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('No memos found'), findsOneWidget);
    });
  });

  testWidgets('memo create / edit / delete flow', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('moost_widget_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    // 疑似 history.jsonl でセッションを 1 件用意する
    final claudeHome = Directory('${tempDir.path}/claude')..createSync();
    File('${claudeHome.path}/history.jsonl').writeAsStringSync(jsonEncode({
      'display': 'test prompt',
      'timestamp': 1700000000000,
      'project': '/tmp/proj',
      'sessionId': 'sess-1',
    }));

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        adapter: ClaudeCodeAdapter(claudeHome: claudeHome.path),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      // --- 登録: 行タップでフォームへ。タイトル初期値 = セッションタイトル
      await tester.tap(find.text('test prompt'));
      await tester.pump();
      expect(find.text('Register Memo'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'test prompt'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), ' tag1, tag2 ,');
      await tester.enterText(find.byType(TextField).at(2), 'memo body');
      await tester.tap(find.text('Save'));
      await settle(tester);

      // 保存後はメモ一覧タブに戻る（design.md 6.3: 戻り先タブ制御）
      expect(find.text('test prompt'), findsOneWidget);
      expect(find.textContaining('tag1, tag2'), findsOneWidget);

      // --- 編集: タイトルを変更して保存
      await tester.tap(find.text('test prompt'));
      await tester.pump();
      expect(find.text('Edit Memo'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'renamed title');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('renamed title'), findsOneWidget);

      // --- 削除: インライン確認を経て削除（ダイアログは出さない）
      await tester.tap(find.text('renamed title'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(find.text('Delete this memo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      expect(find.text('No memos found'), findsOneWidget);
    });
  });

  testWidgets('session detail runs summary and caches it', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('moost_widget_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final adapter = _FakeAdapter([
      RecentSession(
        sessionId: 'sess-1',
        projectPath: '/tmp/proj',
        lastPrompt: 'do something',
        updatedAt: DateTime.utc(2026, 7, 9),
        aiTitle: 'My Session',
      ),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        adapter: adapter,
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      // セッション詳細アイコンを開く
      await tester.tap(find.byTooltip('Session Detail'));
      await tester.pump();
      expect(find.text('My Session'), findsOneWidget);
      expect(find.textContaining('consumes your usage quota'),
          findsOneWidget);

      // 要約実行 → フェイクの要約結果が出る
      await tester.tap(find.text('Summarize with Claude'));
      await settle(tester);
      expect(find.text('SUMMARY: sess-1 recent 1'), findsOneWidget);
      expect(adapter.summarizeCalls, 1);

      // 戻って開き直すとキャッシュから出る（再実行しない）
      await tester.tap(find.text('Back'));
      await settle(tester);
      await tester.tap(find.byTooltip('Session Detail'));
      await tester.pump();
      expect(find.text('SUMMARY: sess-1 recent 1'), findsOneWidget);
      expect(adapter.summarizeCalls, 1);
    });
  });

  testWidgets('save is disabled while title is empty', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('moost_widget_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final claudeHome = Directory('${tempDir.path}/claude')..createSync();
    File('${claudeHome.path}/history.jsonl').writeAsStringSync(jsonEncode({
      'display': 'p',
      'timestamp': 1700000000000,
      'project': '/tmp/proj',
      'sessionId': 'sess-1',
    }));

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        adapter: ClaudeCodeAdapter(claudeHome: claudeHome.path),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      await tester.tap(find.text('p'));
      await tester.pump();

      // タイトルを空にすると保存ボタンが無効になる
      await tester.enterText(find.byType(TextField).at(0), '   ');
      await tester.pump();
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });
}

/// テスト用の AgentAdapter。要約はセッションID・範囲を埋め込んだ固定文字列を返す。
class _FakeAdapter implements AgentAdapter {
  final List<RecentSession> _sessions;
  int summarizeCalls = 0;

  _FakeAdapter(this._sessions);

  @override
  String get agentId => 'fake';

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async =>
      _sessions;

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) =>
      'cd $projectPath && claude --resume $sessionId';

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async {
    summarizeCalls++;
    final label = scope == SummaryScope.full ? 'full' : 'recent $rallies';
    return 'SUMMARY: $sessionId $label';
  }
}
