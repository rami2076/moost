import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/tray/popover_position.dart';

void main() {
  const windowSize = Size(570, 660);

  // 主ディスプレイ（1512x982、メニューバー分 top=38）と
  // その右に置いた拡張ディスプレイ（1920x1055、top=25 起点 x=1512）
  const primary = Rect.fromLTWH(0, 38, 1512, 944);
  const extended = Rect.fromLTWH(1512, 25, 1920, 1055);
  const areas = [primary, extended];

  group('popoverPosition', () {
    test('primary display: centers under the icon', () {
      // クランプが効かない中央寄りのアイコン
      const icon = Rect.fromLTWH(700, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(712, 12),
        iconBounds: icon,
        workAreas: areas,
      );
      expect(position!.dy, icon.bottom + 6);
      // アイコン中央揃え
      expect(position.dx, icon.center.dx - windowSize.width / 2);
    });

    test('primary display: clamps to the right edge near the tray corner',
        () {
      // 右端付近のアイコン → 右端からはみ出さない
      const icon = Rect.fromLTWH(1300, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(1312, 12),
        iconBounds: icon,
        workAreas: areas,
      );
      expect(position!.dx, primary.right - windowSize.width - 8);
    });

    test('extended display: opens on the clicked display, not the primary',
        () {
      // 拡張ディスプレイ側のメニューバーをクリック。
      // trayManager.getBounds() は主ディスプレイのアイコンを返す想定（バグの再現条件）
      const staleIcon = Rect.fromLTWH(1300, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(2500, 10),
        iconBounds: staleIcon,
        workAreas: areas,
      );
      // 拡張ディスプレイの作業領域に収まる（主ディスプレイへ引き戻されない）
      expect(position!.dx, greaterThanOrEqualTo(extended.left + 8));
      expect(position.dx + windowSize.width,
          lessThanOrEqualTo(extended.right - 8));
      // アイコンは別ディスプレイの値なのでカーソル基準・メニューバー直下
      expect(position.dx, const Offset(2500, 10).dx - windowSize.width / 2);
      expect(position.dy, extended.top + 6);
    });

    test('extended display: icon bounds on the same display are preferred',
        () {
      const icon = Rect.fromLTWH(3300, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(3312, 12),
        iconBounds: icon,
        workAreas: areas,
      );
      expect(position!.dy, icon.bottom + 6);
      // 右端クランプが拡張ディスプレイの右端基準で効く
      expect(position.dx, extended.right - windowSize.width - 8);
    });

    test('clamps to the left edge of the display', () {
      const icon = Rect.fromLTWH(10, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(22, 12),
        iconBounds: icon,
        workAreas: areas,
      );
      expect(position!.dx, primary.left + 8);
    });

    test('falls back to icon center when the cursor is unavailable', () {
      const icon = Rect.fromLTWH(1300, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: null,
        iconBounds: icon,
        workAreas: areas,
      );
      expect(position, isNotNull);
      expect(position!.dy, icon.bottom + 6);
    });

    test('legacy behavior when no display info is available', () {
      const icon = Rect.fromLTWH(1300, 0, 24, 24);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(1312, 12),
        iconBounds: icon,
        workAreas: const [],
      );
      expect(position,
          Offset(icon.center.dx - windowSize.width / 2, icon.bottom + 6));
    });

    test('returns null when nothing is known', () {
      expect(
        popoverPosition(
          windowSize: windowSize,
          cursor: null,
          iconBounds: null,
          workAreas: areas,
        ),
        isNull,
      );
      expect(
        popoverPosition(
          windowSize: windowSize,
          cursor: null,
          iconBounds: null,
          workAreas: const [],
        ),
        isNull,
      );
    });

    test('narrow display: pins to the left margin instead of overflowing',
        () {
      const narrow = Rect.fromLTWH(0, 38, 500, 700);
      final position = popoverPosition(
        windowSize: windowSize,
        cursor: const Offset(250, 12),
        iconBounds: null,
        workAreas: const [narrow],
      );
      expect(position!.dx, narrow.left + 8);
    });
  });
}
