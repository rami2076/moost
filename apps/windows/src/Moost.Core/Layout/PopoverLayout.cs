namespace Moost.Core;

/// <summary>UI に依存しない矩形（DIP 単位）。ポップオーバー配置の計算に使う。</summary>
public readonly record struct LayoutRect(double Left, double Top, double Width, double Height)
{
    public double Right => Left + Width;

    public double Bottom => Top + Height;

    public double CenterX => Left + (Width / 2);

    public double CenterY => Top + (Height / 2);
}

/// <summary>
/// ポップオーバーの表示位置を計算する純粋ロジック（UI 非依存・テスト可能）。
///
/// **macOS との違い**: macOS はメニューバーが画面上端にあるためポップオーバーを
/// 「アイコンの直下」に出すが、Windows はタスクトレイが**画面下端（右下）**にあるため
/// 「作業領域の右下に寄せて、タスクトレイの上側」に出す。上下が逆になるのが正しい。
///
/// マルチディスプレイでは、クリック時のカーソルを含む（最も近い）作業領域を選ぶ
/// （macOS の Issue #16 と同じ方針）。
/// </summary>
public static class PopoverLayout
{
    /// <summary>トレイとポップオーバーの間隔。</summary>
    public const double Gap = 6;

    /// <summary>画面端からの余白。</summary>
    public const double Margin = 8;

    /// <summary>
    /// 作業領域の右下に寄せて、上側に収まる位置を返す。決められない場合は null。
    /// </summary>
    /// <param name="windowWidth">ウィンドウ幅（DIP）。</param>
    /// <param name="windowHeight">ウィンドウ高さ（DIP）。</param>
    /// <param name="cursor">クリック時のカーソル位置（DIP）。null なら決めない。</param>
    /// <param name="workAreas">各ディスプレイの作業領域（タスクバーを除く・DIP）。</param>
    public static (double Left, double Top)? PositionAboveTray(
        double windowWidth,
        double windowHeight,
        (double X, double Y)? cursor,
        IReadOnlyList<LayoutRect> workAreas)
    {
        if (workAreas.Count == 0 || cursor is not { } point)
        {
            return null;
        }

        var area = NearestArea(workAreas, point);

        // 右下寄せ（タスクトレイの位置に近づける）
        var left = area.Right - windowWidth - Margin;
        var minLeft = area.Left + Margin;
        if (left < minLeft)
        {
            // 画面がウィンドウより狭い場合は左端合わせを優先する（はみ出さない）
            left = minLeft;
        }

        var top = area.Bottom - windowHeight - Margin;
        var minTop = area.Top + Margin;
        if (top < minTop)
        {
            top = minTop;
        }

        return (left, top);
    }

    /// <summary>
    /// 点に最も近い作業領域を返す。点を含む領域は距離 0 で必ず選ばれる。
    /// トレイ上のクリックは作業領域の外側（タスクバー内）になるため、
    /// 含有判定ではなく最近傍で選ぶことで、タスクバーが左右・上にある配置でも解決できる。
    /// </summary>
    public static LayoutRect NearestArea(IReadOnlyList<LayoutRect> areas, (double X, double Y) point)
    {
        if (areas.Count == 0)
        {
            throw new ArgumentException("作業領域が 1 つもありません。", nameof(areas));
        }

        var best = areas[0];
        var bestDistance = double.PositiveInfinity;

        foreach (var area in areas)
        {
            var dx = point.X < area.Left
                ? area.Left - point.X
                : (point.X > area.Right ? point.X - area.Right : 0);
            var dy = point.Y < area.Top
                ? area.Top - point.Y
                : (point.Y > area.Bottom ? point.Y - area.Bottom : 0);
            var distance = (dx * dx) + (dy * dy);
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = area;
            }
        }

        return best;
    }
}
