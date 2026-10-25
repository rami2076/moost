using System.IO;
using System.Windows;
using System.Windows.Controls;
using Moost.Core;

namespace Moost.WindowsApp.Views;

/// <summary>設定（design.md 6.6）。自動起動だけは OS の実状態を正とする（C4）。</summary>
public partial class SettingsScreen : UserControl
{
    private readonly MainViewModel _viewModel;
    private readonly IAppNavigator _navigator;

    public SettingsScreen(MainViewModel viewModel, IAppNavigator navigator)
    {
        _viewModel = viewModel;
        _navigator = navigator;
        InitializeComponent();

        var settings = viewModel.Settings;
        TerminalAppBox.Text = settings.TerminalApp;
        LimitBox.Text = settings.RecentSessionLimit.ToString(System.Globalization.CultureInfo.CurrentCulture);
        ClaudePathBox.Text = settings.ClaudePath;
        RallyBox.Text = settings.SummaryRallyCount.ToString(System.Globalization.CultureInfo.CurrentCulture);
        PiProviderBox.Text = settings.PiProvider;
        PiModelBox.Text = settings.PiModel;
        CopyAnimationBox.IsChecked = settings.CopyAnimation;
        AutoStartBox.IsChecked = viewModel.AutoStartEnabled;
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        var settings = _viewModel.Settings with
        {
            TerminalApp = TerminalAppBox.Text,
            RecentSessionLimit = ParseInt(LimitBox.Text, 20, 5, 100),
            ClaudePath = ClaudePathBox.Text,
            SummaryRallyCount = ParseInt(RallyBox.Text, 1, 1, 20),
            PiProvider = PiProviderBox.Text,
            PiModel = PiModelBox.Text,
            CopyAnimation = CopyAnimationBox.IsChecked == true,
        };
        _viewModel.SaveSettings(settings);

        // 自動起動は設定ファイルに保存しない（OS の実状態を書き換える）
        var executable = Environment.ProcessPath
            ?? Path.Combine(AppContext.BaseDirectory, "Moost.exe");
        _viewModel.SetAutoStart(AutoStartBox.IsChecked == true, executable);

        _navigator.ShowList();
    }

    private static int ParseInt(string text, int fallback, int min, int max) =>
        int.TryParse(text, System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.CurrentCulture, out var value)
            ? Math.Clamp(value, min, max)
            : fallback;

    private void OnBack(object sender, RoutedEventArgs e) => _navigator.ShowList();
}
