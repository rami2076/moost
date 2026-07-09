import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/main.dart';

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
}
