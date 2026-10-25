using System.Windows;
using Moost.Core;

namespace Moost.WindowsApp;

/// <summary>
/// アプリケーションのエントリポイント（トレイ常駐アプリ・#102 / #103）。
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

        var viewModel = new MainViewModel(
            SessionSources.FromHome(),
            MemoStore.DefaultLocation(),
            ProjectStore.DefaultLocation(),
            SettingsStore.DefaultLocation(),
            new TerminalLauncher(),
            copyToClipboard: text => Clipboard.SetText(text),
            autoStart: new AutoStartService(),
            appVersion: AppInfo.Version);

        var window = new PopoverWindow(viewModel);
        // ウィンドウを一度も表示しないため、GC されないよう参照を保持する
        MainWindow = window;

        _tray = new TrayService(window, openLabel: "開く", quitLabel: "終了");
        // 表示のたびに一覧を読み直す（design.md 6.1 の更新タイミング）
        _tray.Shown += (_, _) => window.RefreshAll();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }
}
