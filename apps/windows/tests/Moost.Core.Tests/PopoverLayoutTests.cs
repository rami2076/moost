using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// ポップオーバー配置の計算（#102）。macOS の <c>popover_position_test.dart</c> に対応するが、
/// **Windows はトレイが画面下端**にあるため上下が逆（トレイの上側・右下寄せ）になる。
/// </summary>
public class PopoverLayoutTests
{
    private const double WindowWidth = 570;
    private const double WindowHeight = 660;

    // 主ディスプレイ（1920x1080・タスクバー 40px を除いた作業領域）と
    // 右隣の拡張ディスプレイ（1920x1080・タスクバー 40px）
    private static readonly LayoutRect Primary = new(0, 0, 1920, 1040);
    private static readonly LayoutRect Extended = new(1920, 0, 1920, 1040);

    [Fact]
    public void PrimaryDisplay_PinsToBottomRightAboveTheTaskbar()
    {
        var position = PopoverLayout.PositionAboveTray(
            WindowWidth,
            WindowHeight,
            (1800, 1050),
            [Primary]);

        Assert.NotNull(position);
        // 右端から 8px 内側・下端（作業領域の底）から 8px 上
        Assert.Equal(Primary.Right - WindowWidth - PopoverLayout.Margin, position!.Value.Left);
        Assert.Equal(Primary.Bottom - WindowHeight - PopoverLayout.Margin, position.Value.Top);
    }

    [Fact]
    public void ExtendedDisplay_IsChosenByCursorPosition()
    {
        var position = PopoverLayout.PositionAboveTray(
            WindowWidth,
            WindowHeight,
            (2500, 1050),
            [Primary, Extended]);

        Assert.NotNull(position);
        // カーソルのある拡張ディスプレイ基準で右下に寄る（主ディスプレイへ戻らない）
        Assert.Equal(Extended.Right - WindowWidth - PopoverLayout.Margin, position!.Value.Left);
        Assert.True(position.Value.Left >= Extended.Left + PopoverLayout.Margin);
    }

    [Fact]
    public void NarrowDisplay_PinsToLeftMargin_InsteadOfOverflowing()
    {
        var narrow = new LayoutRect(0, 0, 500, 700);

        var position = PopoverLayout.PositionAboveTray(WindowWidth, WindowHeight, (250, 690), [narrow]);

        Assert.NotNull(position);
        Assert.Equal(narrow.Left + PopoverLayout.Margin, position!.Value.Left);
    }

    [Fact]
    public void ShortDisplay_PinsToTopMargin_InsteadOfOverflowing()
    {
        var shortScreen = new LayoutRect(0, 0, 1920, 600);

        var position = PopoverLayout.PositionAboveTray(WindowWidth, WindowHeight, (1800, 590), [shortScreen]);

        Assert.NotNull(position);
        Assert.Equal(shortScreen.Top + PopoverLayout.Margin, position!.Value.Top);
    }

    [Fact]
    public void ReturnsNull_WhenDisplayInfoIsMissing()
    {
        Assert.Null(PopoverLayout.PositionAboveTray(WindowWidth, WindowHeight, (100, 100), []));
    }

    [Fact]
    public void ReturnsNull_WhenCursorIsUnknown()
    {
        Assert.Null(PopoverLayout.PositionAboveTray(WindowWidth, WindowHeight, cursor: null, [Primary]));
    }

    [Fact]
    public void NearestArea_ReturnsAreaContainingThePoint()
    {
        var nearest = PopoverLayout.NearestArea([Primary, Extended], (3000, 500));
        Assert.Equal(Extended, nearest);
    }

    [Fact]
    public void NearestArea_UsesDistance_ForClicksInsideTheTaskbar()
    {
        // タスクバー上（作業領域の外）のクリックでも、近い方の画面が選ばれる
        var nearest = PopoverLayout.NearestArea([Primary, Extended], (2500, 1070));
        Assert.Equal(Extended, nearest);

        var leftSide = PopoverLayout.NearestArea([Primary, Extended], (100, 1070));
        Assert.Equal(Primary, leftSide);
    }

    [Fact]
    public void NearestArea_Throws_WhenNoAreas()
    {
        Assert.Throws<ArgumentException>(() => PopoverLayout.NearestArea([], (0, 0)));
    }

    [Fact]
    public void GapAndMargin_AreStable()
    {
        // 端の値はテストで固定しておく（UI の見た目が意図せず動かないように）
        Assert.Equal(6, PopoverLayout.Gap);
        Assert.Equal(8, PopoverLayout.Margin);
    }
}
