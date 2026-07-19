import 'dart:ui';

/// ポップオーバーの表示位置の計算（純粋ロジック。TrayService から分離してテスト可能に）。
///
/// マルチディスプレイ対応（Issue #16）:
/// - 基準はクリック時のカーソル位置（= トレイアイコン上）。カーソルに最も近い
///   ディスプレイの作業領域を選び、そのメニューバー直下に出す
/// - アイコン bounds が選ばれたディスプレイ上にあるときだけアイコン中央揃えにする。
///   trayManager.getBounds() はマルチディスプレイで「クリックされた側」の座標を
///   返す保証がないため、別ディスプレイの値ならカーソル x を採用する
/// - x は選ばれた作業領域の内側にクランプする
///
/// 返り値が null のときは呼び出し側でフォールバック（右上アライン等）する。
Offset? popoverPosition({
  required Size windowSize,
  required Offset? cursor,
  required Rect? iconBounds,
  required List<Rect> workAreas,
}) {
  const gap = 6.0;
  const margin = 8.0;

  if (workAreas.isEmpty) {
    // ディスプレイ情報なし: 従来挙動（アイコン直下・クランプなし）に落とす
    if (iconBounds == null) {
      return null;
    }
    return Offset(
      iconBounds.center.dx - windowSize.width / 2,
      iconBounds.bottom + gap,
    );
  }

  final anchor = cursor ?? iconBounds?.center;
  if (anchor == null) {
    return null;
  }

  final area = _nearestArea(workAreas, anchor);

  // アイコンが選ばれたディスプレイのメニューバー上にあるか
  // （作業領域はメニューバーを含まないため、上方向に少し許容して判定する）
  final iconOnArea = iconBounds != null &&
      iconBounds.center.dx >= area.left &&
      iconBounds.center.dx <= area.right &&
      (area.top - iconBounds.bottom).abs() <= 100;

  final anchorX = iconOnArea ? iconBounds.center.dx : anchor.dx;
  final y = iconOnArea ? iconBounds.bottom + gap : area.top + gap;

  var x = anchorX - windowSize.width / 2;
  final minX = area.left + margin;
  final maxX = area.right - windowSize.width - margin;
  // ウィンドウより狭いディスプレイでは左端合わせを優先する
  x = maxX < minX ? minX : x.clamp(minX, maxX);

  return Offset(x, y);
}

/// 点に最も近い作業領域を返す（点を含む領域は距離 0 で必ず選ばれる）。
/// メニューバー上のクリックは作業領域の外側になるため、含有判定でなく
/// 最近傍で選ぶことで縦積み・横並びどちらの配置でも正しく解決する。
Rect _nearestArea(List<Rect> areas, Offset point) {
  Rect best = areas.first;
  var bestDistance = double.infinity;
  for (final area in areas) {
    final dx = point.dx < area.left
        ? area.left - point.dx
        : (point.dx > area.right ? point.dx - area.right : 0.0);
    final dy = point.dy < area.top
        ? area.top - point.dy
        : (point.dy > area.bottom ? point.dy - area.bottom : 0.0);
    final distance = dx * dx + dy * dy;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = area;
    }
  }
  return best;
}
