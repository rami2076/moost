using System.Windows;
using System.Windows.Forms;
using System.Windows.Media;
using Moost.Core;
using Application = System.Windows.Application;
using Point = System.Windows.Point;

namespace Moost.WindowsApp;

/// <summary>
/// タスクトレイ常駐の面倒を見る（design.md 6 章の Windows 版・#102）。
///
/// <list type="bullet">
/// <item>トレイアイコンの左クリック: ポップオーバーの表示/非表示をトグル</item>
/// <item>右クリック: コンテキストメニュー（開く / 終了）</item>
/// <item>ウィンドウのフォーカス喪失: 終了せず隠す（macOS のポップオーバーと同じ体感）</item>
/// <item>タスクバーには出さない（ウィンドウは ShowInTaskbar=false・タスクトレイのみ）</item>
/// </list>
/// </summary>
public sealed class TrayService : IDisposable
{
    /// <summary>フォーカス喪失で隠した直後のトレイクリックを「隠す」と扱う猶予。</summary>
    private static readonly TimeSpan BlurHideGuard = TimeSpan.FromMilliseconds(400);

    private readonly NotifyIcon _notifyIcon;
    private readonly Window _window;
    private readonly Icon _icon;
    private DateTime? _hiddenByBlurAt;

    /// <summary>ウィンドウが表示されるたびに発火する（UI 側は一覧の再読込に使う）。</summary>
    public event EventHandler? Shown;

    public TrayService(Window window, string openLabel, string quitLabel, string iconUri = "pack://application:,,,/Assets/moost.ico")
    {
        _window = window;
        _icon = LoadIcon(iconUri);

        _notifyIcon = new NotifyIcon
        {
            Icon = _icon,
            Text = "Moost",
            Visible = true,
            ContextMenuStrip = BuildMenu(openLabel, quitLabel),
        };
        _notifyIcon.MouseDown += (_, args) =>
        {
            if (args.Button == MouseButtons.Left)
            {
                ToggleWindow();
            }
        };

        // アプリ外を触ったら隠れる（macOS の NSPopover と同じ）
        _window.Deactivated += (_, _) => HideByBlur();

        // 閉じる操作は終了ではなく非表示
        _window.Closing += (_, args) =>
        {
            if (!_shuttingDown)
            {
                args.Cancel = true;
                _window.Hide();
            }
        };
    }

    private bool _shuttingDown;

    /// <summary>トレイのメニューから呼ぶ終了。</summary>
    public void Quit()
    {
        _shuttingDown = true;
        Dispose();
        Application.Current.Shutdown();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _icon.Dispose();
    }

    private ContextMenuStrip BuildMenu(string openLabel, string quitLabel)
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(openLabel, image: null, onClick: (_, _) => ShowWindow());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(quitLabel, image: null, onClick: (_, _) => Quit());
        return menu;
    }

    private static Icon LoadIcon(string iconUri)
    {
        // 単一 exe 配布でも欠けないよう、アイコンは埋め込みリソースから読む
        var resource = Application.GetResourceStream(new Uri(iconUri, UriKind.Absolute))
            ?? throw new InvalidOperationException($"アイコンが見つかりません: {iconUri}");
        using var stream = resource.Stream;
        return new Icon(stream);
    }

    private void HideByBlur()
    {
        if (!_window.IsVisible)
        {
            return;
        }

        _hiddenByBlurAt = DateTime.UtcNow;
        _window.Hide();
    }

    private void ToggleWindow()
    {
        // トレイクリック時、先に blur → hide が走ると「非表示」のつもりが再表示になるため、
        // 直前に blur で隠した場合は「隠す」側に倒す（macOS 実装と同じガード）
        var hiddenJustNow = _hiddenByBlurAt is { } hiddenAt
            && DateTime.UtcNow - hiddenAt < BlurHideGuard;

        if (hiddenJustNow || _window.IsVisible)
        {
            _hiddenByBlurAt = null;
            _window.Hide();
            return;
        }

        ShowWindow();
    }

    private void ShowWindow()
    {
        PositionAboveTray();
        _window.Show();
        _window.Activate();
        _window.Focus();
        Shown?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// カーソルを含む（最も近い）ディスプレイの作業領域の右下・トレイの上側へ配置する。
    /// 位置が決められない場合は右下アラインにフォールバックする。
    /// </summary>
    private void PositionAboveTray()
    {
        var scale = VisualTreeHelper.GetDpi(_window);
        var areas = Screen.AllScreens
            .Select(screen => screen.WorkingArea)
            .Select(area => new LayoutRect(
                area.Left / scale.DpiScaleX,
                area.Top / scale.DpiScaleY,
                area.Width / scale.DpiScaleX,
                area.Height / scale.DpiScaleY))
            .ToArray();

        var cursorPixels = Cursor.Position;
        var cursor = new Point(cursorPixels.X / scale.DpiScaleX, cursorPixels.Y / scale.DpiScaleY);

        var position = PopoverLayout.PositionAboveTray(
            _window.Width,
            _window.Height,
            (cursor.X, cursor.Y),
            areas);

        if (position is not { } target)
        {
            // ディスプレイ情報が取れない場合のフォールバック（作業領域の右下）
            var workArea = SystemParameters.WorkArea;
            _window.Left = workArea.Right - _window.Width - PopoverLayout.Margin;
            _window.Top = workArea.Bottom - _window.Height - PopoverLayout.Margin;
            return;
        }

        _window.Left = target.Left;
        _window.Top = target.Top;
    }
}
