import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/main.dart';
import 'package:moost_desktop/src/update/update_checker.dart';

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

/// コピー成功フィードバックの緑チェックアイコン。
/// （SegmentedButton の選択中タブにも Icons.check が出るため色で絞る）
Finder greenCheckIcon() => find.byWidgetPredicate(
    (widget) =>
        widget is Icon &&
        widget.icon == Icons.check &&
        widget.color == Colors.green);

/// テスト用の一時ディレクトリを作り、競合に耐える teardown を登録する。
///
/// ストアの保存は「.tmp 書き込み → rename」のアトミック方式のため、
/// 保存 I/O が残ったまま teardown がディレクトリを消すと、遅れて走る
/// rename が PathNotFoundException でテストを落とす（CI の遅いランナーで
/// 顕在化）。teardown は FakeAsync ゾーンで走るので同期リトライにする。
Directory createTempDir() {
  final tempDir = Directory.systemTemp.createTempSync('moost_widget_');
  addTearDown(() {
    for (var attempt = 0; ; attempt++) {
      try {
        tempDir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 4) {
          rethrow;
        }
        sleep(const Duration(milliseconds: 50));
      }
    }
  });
  return tempDir;
}

/// 進行中のアトミック書き込み（.tmp → rename）が掃けるまで待つ。
/// runAsync の中（実時間が進むゾーン)で、テスト本体の最後に呼ぶ。
///
/// 「.tmp なし」の一瞬（書き込み開始前）をクリーンと誤判定しないよう、
/// まず実時間を置いてから、連続してクリーンであることを確認する。
Future<void> drainPendingWrites(Directory tempDir) async {
  var cleanStreak = 0;
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final hasTmp = tempDir
        .listSync(recursive: true)
        .any((entity) => entity.path.endsWith('.tmp'));
    cleanStreak = hasTmp ? 0 : cleanStreak + 1;
    if (cleanStreak >= 5) {
      return;
    }
  }
}

void main() {
  testWidgets('renders session list tab with empty stores', (tester) async {
    // FakeAsync ゾーン（runAsync の外）では非同期 I/O の Future が完了しない
    // ため、テンポラリディレクトリ操作は同期 API を使う
    final tempDir = createTempDir();

    // 実ファイル I/O を伴う Future は FakeAsync では完了しないため、
    // テスト全体を runAsync 内で実行し、pump を明示的に打つ
    // （スピナーのアニメーションがあるため pumpAndSettle は使えない）
    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        // 存在しないディレクトリを指す adapter → 空一覧になる
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
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
    final tempDir = createTempDir();

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
        registry:
            AdapterRegistry([ClaudeCodeAdapter(claudeHome: claudeHome.path)]),
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

      // 削除の保存 I/O が残ったまま teardown に入らないよう掃ける
      await drainPendingWrites(tempDir);
    });
  });

  testWidgets('memo list row delete with inline confirmation',
      (tester) async {
    final tempDir = createTempDir();

    // メモを 1 件持つストアを直接用意する（登録フローは別テストで担保済み）
    final now = DateTime.utc(2026, 7, 16).toIso8601String();
    File('${tempDir.path}/memos.json').writeAsStringSync(jsonEncode({
      'schemaVersion': 1,
      'memos': [
        {
          'id': 'memo-1',
          'agent': 'claude-code',
          'sessionId': 'sess-1',
          'title': 'row memo',
          'tags': <String>[],
          'body': '',
          'projectPath': '/tmp/proj',
          'createdAt': now,
          'updatedAt': now,
        },
      ],
    }));

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      await tester.tap(find.text('Memos'));
      await settle(tester);
      expect(find.text('row memo'), findsOneWidget);

      // ゴミ箱アイコン → 一覧上部にタイトル入りの確認バーが出る
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(find.text('Delete "row memo"?'), findsOneWidget);

      // キャンセルでバーが消え、メモは残る
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Delete "row memo"?'), findsNothing);
      expect(find.text('row memo'), findsOneWidget);

      // もう一度ゴミ箱 → 削除で確定するとメモが消える
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      expect(find.text('No memos found'), findsOneWidget);

      await drainPendingWrites(tempDir);
    });
  });

  testWidgets('update notice appears in the footer and copies brew command',
      (tester) async {
    final tempDir = createTempDir();

    final openedUrls = <Uri>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => true,
        openUrl: (url) async => openedUrls.add(url),
      ));
      await settle(tester);

      // フッターに更新ボタンが出る
      expect(find.text('v9.9.9 available'), findsOneWidget);

      // brew 導入なので、タップでコマンドがコピーされ
      // アイコンが緑のチェックに変わる（スナックバーは出さない）
      await tester.tap(find.text('v9.9.9 available'));
      await settle(tester);
      expect(greenCheckIcon(), findsOneWidget);
      expect(openedUrls, isEmpty);
    });
  });

  testWidgets('update notice opens the release page for manual installs',
      (tester) async {
    final tempDir = createTempDir();

    final openedUrls = <Uri>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => false,
        openUrl: (url) async => openedUrls.add(url),
      ));
      await settle(tester);

      await tester.tap(find.text('v9.9.9 available'));
      await settle(tester);
      expect(openedUrls, [
        Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
      ]);
    });
  });

  testWidgets('session detail runs summary and caches it', (tester) async {
    final tempDir = createTempDir();

    final adapter = _FakeAdapter([
      RecentSession(
        agentId: 'fake',
        sessionId: 'sess-1',
        projectPath: '/tmp/proj',
        lastPrompt: 'do something',
        updatedAt: DateTime.utc(2026, 7, 9),
        aiTitle: 'My Session',
      ),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry([adapter]),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      // セッション行にターミナル起動ボタンが並ぶ
      expect(find.byTooltip('Open in terminal'), findsOneWidget);

      // 復帰コマンドのコピー成功 → 円周スイープが完了するとアイコンが
      // 緑のチェックに変わる
      await tester.tap(find.byTooltip('Copy resume command'));
      await settle(tester); // 非同期のコピー完了・スイープ開始
      await tester.pump(const Duration(milliseconds: 600)); // スイープ完了
      await tester.pump();
      expect(greenCheckIcon(), findsOneWidget);

      // 最終利用日時がサブタイトル行に出る（表示はローカル時刻・en ロケール）
      final localUpdated = DateTime.utc(2026, 7, 9).toLocal();
      String pad(int n) => n.toString().padLeft(2, '0');
      expect(
        find.text('${localUpdated.month}/${localUpdated.day} '
            '${pad(localUpdated.hour)}:${pad(localUpdated.minute)}'),
        findsOneWidget,
      );

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

  testWidgets('footer opens settings and notes, then returns',
      (tester) async {
    final tempDir = createTempDir();

    final claudeHome = Directory('${tempDir.path}/claude')..createSync();

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry:
            AdapterRegistry([ClaudeCodeAdapter(claudeHome: claudeHome.path)]),
        memoStore: MemoStore(File('${tempDir.path}/memos.json')),
        settingsStore: SettingsStore(File('${tempDir.path}/settings.json')),
      ));
      await settle(tester);

      // 設定を開く → 復帰先ターミナルの項目が見える
      await tester.tap(find.widgetWithText(TextButton, 'Settings'));
      await settle(tester);
      expect(find.text('Resume terminal'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await settle(tester);

      // 注意を開く → 利用枠の説明が見える
      await tester.tap(find.widgetWithText(TextButton, 'Notes'));
      await tester.pump();
      expect(find.text('About summaries'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await settle(tester);
      expect(find.text('No sessions found'), findsOneWidget);
    });
  });

  testWidgets('save is disabled while title is empty', (tester) async {
    final tempDir = createTempDir();

    final claudeHome = Directory('${tempDir.path}/claude')..createSync();
    File('${claudeHome.path}/history.jsonl').writeAsStringSync(jsonEncode({
      'display': 'p',
      'timestamp': 1700000000000,
      'project': '/tmp/proj',
      'sessionId': 'sess-1',
    }));

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry:
            AdapterRegistry([ClaudeCodeAdapter(claudeHome: claudeHome.path)]),
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

/// テスト用の UpdateChecker。ネットワークに出ず固定の結果を返す。
class _FakeUpdateChecker extends UpdateChecker {
  final UpdateInfo? _info;

  _FakeUpdateChecker(this._info) : super(currentVersion: '0.0.0');

  @override
  Future<UpdateInfo?> check() async => _info;
}

/// テスト用の AgentAdapter。要約はセッションID・範囲を埋め込んだ固定文字列を返す。
class _FakeAdapter implements AgentAdapter {
  final List<RecentSession> _sessions;
  int summarizeCalls = 0;

  _FakeAdapter(this._sessions);

  @override
  String get agentId => 'fake';

  @override
  String get displayName => 'Claude';

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
