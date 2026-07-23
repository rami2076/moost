import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/main.dart';
import 'package:moost_desktop/src/update/brew_updater.dart';
import 'package:moost_desktop/src/update/update_checker.dart';

import 'fakes.dart';

/// runAsync の中で実 I/O の完了を待ちながらフレームを進める。
///
/// I/O が連鎖する操作（保存 → 画面遷移 → 再読込）の後、次のアクションに
/// 移る前に軽くフレームを進めておくための汎用ユーティリティ。
/// 「特定の文言/ウィジェットが出るまで」を検証する箇所では、固定時間待ちの
/// 代わりに [waitFor] / [waitForGone] を使うこと（Issue #30: 固定 200ms が
/// CI の共有ランナーでは足りず断続的に失敗する事例があったため、
/// ポーリング方式に置き換えた）。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump();
  }
}

/// [waitFor] / [waitForGone] の共通実装。[ready] が true を返すまで
/// ポーリングし、実際にかかった時間を必ず標準出力へ残す（Issue #30:
/// CI でどのくらいの待ち時間が実際に必要だったかを次回の判断材料にするため。
/// タイムアウトしても例外は投げず、直後の `expect` に判断を委ねる）。
Future<void> _pollUntil(
  WidgetTester tester,
  String label,
  bool Function() ready,
  Duration timeout,
) async {
  final stopwatch = Stopwatch()..start();
  final deadline = DateTime.now().add(timeout);

  // 高速フェーズ: 実時間を挟まずに数フレーム進めてみる。フェイクストアの
  // ようにマイクロタスクだけで完結する処理は、ここで実時間ゼロのまま
  // 見つかる（Issue #30 フォローアップ: フェイク化した効果を測定に出すため）。
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    if (ready()) {
      // ignore: avoid_print
      print('[$label] ready after ${stopwatch.elapsedMilliseconds}ms (fast)');
      return;
    }
  }

  // 低速フェーズ: 実際の I/O やタイマーの完了を実時間待ちしながら待つ。
  while (true) {
    if (ready()) {
      // ignore: avoid_print
      print('[$label] ready after ${stopwatch.elapsedMilliseconds}ms');
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      // ignore: avoid_print
      print('[$label] TIMED OUT after ${stopwatch.elapsedMilliseconds}ms '
          '(budget: ${timeout.inMilliseconds}ms)');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tester.pump();
  }
}

/// [finder] が最低1件見つかるまでポーリングする。
///
/// settle() の固定時間待ちと違い、条件が満たされた時点で即座に抜けるため
/// 速いマシンでは無駄に待たない。CI の遅いランナーでも [timeout] まで
/// 辛抱強く待つ。
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) =>
    _pollUntil(tester, 'waitFor $finder',
        () => finder.evaluate().isNotEmpty, timeout);

/// [finder] が消えるまでポーリングする（[waitFor] の逆）。
Future<void> waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) =>
    _pollUntil(
        tester, 'waitForGone $finder', () => finder.evaluate().isEmpty, timeout);

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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
      ));
      // 空状態の文言が出る（英語ロケールがデフォルト）
      await waitFor(tester, find.text('No sessions found'));
      expect(find.text('No sessions found'), findsOneWidget);

      // メモタブへ切替
      await tester.tap(find.text('Memos'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('No memos found'), findsOneWidget);
    });
  });

  testWidgets(
      'tapping the copy icon while its feedback is busy does not fall '
      'through to the row tap (navigate to memo form)', (tester) async {
    // 回帰テスト: onPressed を null にして busy を表現すると IconButton が
    // タップを消費しなくなり、親の ListTile.onTap（メモ登録画面への遷移）
    // へ素通りしてしまうバグがあった
    final tempDir = createTempDir();

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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
      ));
      await settle(tester);

      final copyButton = find.byTooltip('Copy resume command');

      // 1 回目: コピー実行 → スイープ開始（busy）
      await tester.tap(copyButton);
      await tester.pump();

      // 2 回目: busy 中に同じアイコンを連打しても、行の onTap（メモ登録
      // 画面への遷移）へは伝播しない
      await tester.tap(copyButton);
      await tester.pump();
      expect(find.text('Register Memo'), findsNothing);
      expect(find.text('test prompt'), findsOneWidget);

      // フィードバックが完全に終わってから行をタップすると、通常どおり
      // メモ登録画面へ遷移する（誤検知でないことの確認）
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('test prompt'));
      await tester.pump();
      expect(find.text('Register Memo'), findsOneWidget);
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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
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
      // find.text('test prompt') は保存前の TextField 自体の初期値
      // （セッションタイトル由来）にも一致してしまい早期に抜けるため、
      // 登録フォーム自体が消えたのを確認してから、一覧の再読込完了
      // （'test prompt' の再表示）を別途待つ
      await waitForGone(tester, find.text('Register Memo'));
      await waitFor(tester, find.text('test prompt'));

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
      // find.text('renamed title') は保存前の TextField 自体の入力値にも
      // 一致してしまい早期に抜けるため、編集画面自体が消えたのを確認して
      // から、一覧の再読込完了（'renamed title' の再表示）を別途待つ
      await waitForGone(tester, find.text('Edit Memo'));
      await waitFor(tester, find.text('renamed title'));
      expect(find.text('renamed title'), findsOneWidget);

      // --- 削除: インライン確認を経て削除（ダイアログは出さない）
      await tester.tap(find.text('renamed title'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      expect(find.text('Delete this memo?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(tester, find.text('No memos found'));
      expect(find.text('No memos found'), findsOneWidget);

      // 削除の保存 I/O が残ったまま teardown に入らないよう掃ける
      await drainPendingWrites(tempDir);
    });
  });

  testWidgets('memo list row delete with inline confirmation',
      (tester) async {
    final tempDir = createTempDir();

    // メモを 1 件持つストアを直接用意する（登録フローは別テストで担保済み）
    final now = DateTime.utc(2026, 7, 16);
    final memoStore = FakeMemoStore([
      Memo(
        id: 'memo-1',
        agent: 'claude-code',
        sessionId: 'sess-1',
        title: 'row memo',
        tags: const [],
        body: '',
        projectPath: '/tmp/proj',
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: memoStore,
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
      ));
      await settle(tester);

      await tester.tap(find.text('Memos'));
      await waitFor(tester, find.text('row memo'));
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
      await waitFor(tester, find.text('No memos found'));
      expect(find.text('No memos found'), findsOneWidget);

      await drainPendingWrites(tempDir);
    });
  });

  testWidgets('project register / launch buttons / delete flow',
      (tester) async {
    final tempDir = createTempDir();

    // 登録済みプロジェクトを1件持つストアを直接用意する
    final projectStore = FakeProjectStore([
      Project(
        id: 'proj-1',
        projectPath: '/tmp/existing-project',
        createdAt: DateTime.utc(2026, 7, 20),
      ),
    ]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry([
          ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude'),
          CodexAdapter(codexHome: '${tempDir.path}/codex'),
        ]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: projectStore,
        pickFolder: () async => '/tmp/new-project',
      ));
      await settle(tester);

      await tester.tap(find.text('Projects'));
      await waitFor(tester, find.text('existing-project'));
      expect(find.text('existing-project'), findsOneWidget);
      expect(find.text('/tmp/existing-project'), findsOneWidget);

      // エージェントごとの起動ボタンと削除ボタンが1行に並ぶ（ADR-004）
      expect(find.byTooltip('Start new session with Claude'), findsOneWidget);
      expect(find.byTooltip('Start new session with Codex'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);

      // Claude/Codex は頭文字が同じで見分けが付かず、公式ロゴも使えないため
      // 色で区別する（商標ガイドライン: 各社とも無提携の第三者利用は不許可）
      final claudeIcon = tester.widget<Icon>(find.descendant(
        of: find.byTooltip('Start new session with Claude'),
        matching: find.byType(Icon),
      ));
      final codexIcon = tester.widget<Icon>(find.descendant(
        of: find.byTooltip('Start new session with Codex'),
        matching: find.byType(Icon),
      ));
      expect(claudeIcon.color, isNotNull);
      expect(codexIcon.color, isNotNull);
      expect(claudeIcon.color, isNot(codexIcon.color));

      // 登録: フォルダ選択（フェイク注入）→ 一覧に追加される
      await tester.tap(find.text('Register'));
      await waitFor(tester, find.text('new-project'));
      expect(find.text('new-project'), findsOneWidget);

      // 削除（登録解除）: インライン確認を経由する
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pump();
      expect(find.text('Unregister "existing-project"?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitForGone(tester, find.text('existing-project'));
      expect(find.text('existing-project'), findsNothing);
      expect(find.text('new-project'), findsOneWidget);

      await drainPendingWrites(tempDir);
    });
  });

  testWidgets(
      'update notice: brew flow goes idle -> confirm -> running -> restart',
      (tester) async {
    final tempDir = createTempDir();

    var restarted = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => true,
        brewUpdater: _FakeBrewUpdater(),
        onRestart: () async => restarted = true,
      ));
      await settle(tester);

      // idle: 固定ラベル「Update」+ ツールチップにバージョン
      expect(find.text('Update'), findsOneWidget);
      expect(find.byTooltip('v9.9.9 available'), findsOneWidget);

      // タップで確認（Yes/No）に切り替わる
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(find.text('Update now?'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);

      // Yes → 実行中（不確定インジケーター）→ 完了で再起動ボタン
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(find.text('Updating…'), findsOneWidget);
      await waitFor(tester, find.text('Restart'));
      expect(find.text('Restart'), findsOneWidget);

      // 再起動ボタンは押すまで自動実行されない
      expect(restarted, isFalse);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(restarted, isTrue);
    });
  });

  testWidgets(
      'update notice: No on the update confirm offers to copy the command',
      (tester) async {
    final tempDir = createTempDir();

    await tester.runAsync(() async {
      final brewUpdater = _FakeBrewUpdater();
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => true,
        brewUpdater: brewUpdater,
      ));
      await settle(tester);

      // 「アップデートしますか?」で No → 実行はせず、コピーするか尋ねる
      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.tap(find.text('No'));
      await tester.pump();
      expect(find.text('Copy the update command instead?'), findsOneWidget);
      expect(brewUpdater.runCalls, 0);

      // そこで No → 最初（idle）に戻る
      await tester.tap(find.text('No'));
      await tester.pump();
      expect(find.text('Update'), findsOneWidget);
      expect(brewUpdater.runCalls, 0);
    });
  });

  testWidgets(
      'update notice: Yes on the copy offer copies the command and reverts',
      (tester) async {
    final tempDir = createTempDir();

    await tester.runAsync(() async {
      final brewUpdater = _FakeBrewUpdater();
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => true,
        brewUpdater: brewUpdater,
      ));
      await settle(tester);

      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.tap(find.text('No'));
      await tester.pump();
      expect(find.text('Copy the update command instead?'), findsOneWidget);

      // 「はい」は他のミニボタンと同じテキストボタン（アイコンではない）
      await tester.tap(find.text('Yes'));
      // Clipboard.setData の非同期完了を待つ
      await waitFor(tester, find.text('Command copied'));

      expect(find.text('Command copied'), findsOneWidget);
      expect(greenCheckIcon(), findsOneWidget);
      expect(brewUpdater.runCalls, 0); // brew は実行しない、コピーのみ

      // しばらくすると自動で idle に戻る（実時間の Timer なので、
      // pump(duration) ではなく実際に待つ）
      await Future<void>.delayed(const Duration(milliseconds: 3100));
      await tester.pump();
      expect(find.text('Update'), findsOneWidget);
    });
  });

  testWidgets('update notice: brew failure shows a retry-capable error',
      (tester) async {
    final tempDir = createTempDir();

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry: AdapterRegistry(
            [ClaudeCodeAdapter(claudeHome: '${tempDir.path}/claude')]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => true,
        brewUpdater: _FakeBrewUpdater(shouldFail: true),
      ));
      await settle(tester);

      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.tap(find.text('Yes'));
      await settle(tester);

      // 失敗するとエラーアイコン付きで「Update」に戻る（再試行できる）
      expect(find.text('Update'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // 再タップで確認画面に戻れる（再試行導線）
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(find.text('Update now?'), findsOneWidget);
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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        updateChecker: _FakeUpdateChecker(UpdateInfo(
          version: '9.9.9',
          releaseUrl:
              Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
        )),
        isBrewManaged: () => false,
        openUrl: (url) async => openedUrls.add(url),
      ));
      await settle(tester);

      // 手動導入は確認を挟まず、タップで直接リリースページを開く
      await tester.tap(find.text('Update'));
      await settle(tester);
      expect(openedUrls, [
        Uri.parse('https://github.com/rami2076/moost/releases/tag/v9.9.9'),
      ]);
    });
  });

  testWidgets('session detail runs summary and caches it', (tester) async {
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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
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
      await waitFor(tester, find.text('SUMMARY: sess-1 recent 1'));
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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
      ));
      await settle(tester);

      // フッターに Quit はない（設定画面に移動した）
      expect(find.widgetWithText(TextButton, 'Quit'), findsNothing);

      // 設定を開く → 復帰先ターミナルの項目が見える
      await tester.tap(find.widgetWithText(TextButton, 'Settings'));
      await waitFor(tester, find.text('Resume terminal'));
      expect(find.text('Resume terminal'), findsOneWidget);
      // appVersion 未指定なのでバージョン行は出ない
      expect(find.textContaining('Version'), findsNothing);
      // Quit はここにある（デバッグ欄の分、ListView が遅延ビルドする
      // 範囲外になっていることがあるため、見えるまでスクロールする）
      final quitButton = find.widgetWithText(TextButton, 'Quit');
      await tester.dragUntilVisible(
        quitButton,
        find.byType(ListView),
        const Offset(0, -50),
      );
      expect(quitButton, findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await settle(tester);

      // 注意を開く → 利用枠の説明が見える
      await tester.tap(find.widgetWithText(TextButton, 'Notes'));
      await tester.pump();
      expect(find.text('About summaries'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await waitFor(tester, find.text('No sessions found'));
      expect(find.text('No sessions found'), findsOneWidget);
    });
  });

  testWidgets('settings screen shows the app version when provided',
      (tester) async {
    final tempDir = createTempDir();

    final claudeHome = Directory('${tempDir.path}/claude')..createSync();

    await tester.runAsync(() async {
      await tester.pumpWidget(MoostApp(
        registry:
            AdapterRegistry([ClaudeCodeAdapter(claudeHome: claudeHome.path)]),
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
        appVersion: '1.5.0',
      ));
      await settle(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Settings'));
      await waitFor(tester, find.text('Version 1.5.0'));
      expect(find.text('Version 1.5.0'), findsOneWidget);
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
        memoStore: FakeMemoStore(),
        settingsStore: FakeSettingsStore(),
        projectStore: FakeProjectStore(),
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

/// テスト用の BrewUpdater。実際の brew は呼ばない。
class _FakeBrewUpdater extends BrewUpdater {
  final bool shouldFail;
  int runCalls = 0;

  _FakeBrewUpdater({this.shouldFail = false});

  @override
  Future<void> run() async {
    runCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (shouldFail) {
      throw const BrewUpdateException('boom');
    }
  }
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
  String buildNewSessionCommand({required String projectPath}) =>
      'cd $projectPath && claude';

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
