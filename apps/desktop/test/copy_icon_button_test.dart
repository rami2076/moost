import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/widgets/copy_icon_button.dart';

void main() {
  setUp(() {
    // グローバルなタイミング設定を各テストで既知の状態に戻す
    CopyFeedbackTiming.animationEnabled.value = true;
    CopyFeedbackTiming.sweepMs.value = 250;
    CopyFeedbackTiming.holdMs.value = 400;
  });

  Finder greenCheckIcon() => find.byWidgetPredicate((widget) =>
      widget is Icon && widget.icon == Icons.check && widget.color == Colors.green);

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('tapping during the sweep+hold feedback is ignored',
      (tester) async {
    var copyCount = 0;
    await tester.pumpWidget(wrap(CopyIconButton(
      onCopy: () async {
        copyCount++;
      },
    )));

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    // スイープ中に連打しても無視される
    await tester.tap(find.byType(IconButton));
    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 100));

    // チェック表示中（hold）に連打しても無視される
    await tester.pump(const Duration(milliseconds: 300)); // スイープ完了
    await tester.tap(find.byType(IconButton));
    expect(greenCheckIcon(), findsOneWidget);

    expect(copyCount, 1);
  });

  testWidgets('a new tap is accepted once feedback fully reverts',
      (tester) async {
    // pumpAndSettle は Timer による hold 待機を待ちきらないことがあるため、
    // widget_test.dart の慣例どおり明示的な pump で経過時間を進める
    var copyCount = 0;
    await tester.pumpWidget(wrap(CopyIconButton(
      onCopy: () async {
        copyCount++;
      },
    )));

    await tester.tap(find.byType(IconButton));
    await tester.pump(); // onCopy 完了・スイープ開始
    await tester.pump(const Duration(milliseconds: 300)); // スイープ完了
    await tester.pump(const Duration(milliseconds: 450)); // hold 完了・復帰
    expect(copyCount, 1);
    expect(greenCheckIcon(), findsNothing);

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(copyCount, 2);
  });

  testWidgets('animation disabled: still blocks re-tap during the 1s hold',
      (tester) async {
    CopyFeedbackTiming.animationEnabled.value = false;
    var copyCount = 0;
    await tester.pumpWidget(wrap(CopyIconButton(
      onCopy: () async {
        copyCount++;
      },
    )));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(greenCheckIcon(), findsOneWidget);

    // hold の途中（1000ms 未満）で連打しても無視される
    await tester.tap(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(copyCount, 1);

    // hold が完全に終わってから叩くと受け付けられる
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(copyCount, 2);
  });
}
