using System.Windows;

namespace Moost.WindowsApp;

/// <summary>
/// アプリケーションのエントリポイント（トレイ常駐アプリ・#102）。
///
/// 起動時はトレイアイコンだけを出し、ウィンドウはトレイクリックで初めて表示する。
/// ウィンドウを閉じても終了せず、トレイメニューの「終了」で終わる
/// （<see cref="ShutdownMode.OnExplicitShutdown"/>）。
/// </summary>
public partial class App : Application
{
    private TrayService? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        var window = new PopoverWindow();
        // ウィンドウを一度も表示しないため、GC されないよう参照を保持する
        MainWindow = window;

        // 文言は #103 で i18n（l10n）に接続する
        _tray = new TrayService(window, openLabel: "開く", quitLabel: "終了");
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }
}
