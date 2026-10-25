using System.Windows;
using System.Windows.Controls;
using Moost.Core;

namespace Moost.WindowsApp.Views;

/// <summary>セッション詳細 + 要約（design.md 6.1 の sessionDetail / summary）。</summary>
public partial class SessionDetailScreen : UserControl
{
    private readonly MainViewModel _viewModel;
    private readonly IAppNavigator _navigator;
    private readonly RecentSession _session;
    private int _rallies;

    public SessionDetailScreen(MainViewModel viewModel, IAppNavigator navigator, RecentSession session)
    {
        _viewModel = viewModel;
        _navigator = navigator;
        _session = session;
        _rallies = Math.Clamp(viewModel.Settings.SummaryRallyCount, 1, 20);
        // 要約は ViewModel の「選択中セッション」に対して実行される
        viewModel.SelectSessionForMemo(session);
        InitializeComponent();

        TitleText.Text = session.DisplayTitle;
        MetaText.Text =
            $"{AgentVisual.DisplayName(session.AgentId)} · {session.SessionId}\n" +
            $"{session.ProjectPath} · 最終利用 {session.UpdatedAt.ToLocalTime():yyyy/M/d HH:mm}";
        RallyText.Text = _rallies.ToString(System.Globalization.CultureInfo.CurrentCulture);
        SummaryBox.Text = viewModel.SummaryText;
    }

    private void OnRallyMinus(object sender, RoutedEventArgs e) => SetRallies(_rallies - 1);

    private void OnRallyPlus(object sender, RoutedEventArgs e) => SetRallies(_rallies + 1);

    private void SetRallies(int value)
    {
        _rallies = Math.Clamp(value, 1, 20);
        RallyText.Text = _rallies.ToString(System.Globalization.CultureInfo.CurrentCulture);
    }

    private async void OnSummarizeRecent(object sender, RoutedEventArgs e) => await SummarizeAsync(SummaryScope.Recent);

    private async void OnSummarizeFull(object sender, RoutedEventArgs e) => await SummarizeAsync(SummaryScope.Full);

    private async Task SummarizeAsync(SummaryScope scope)
    {
        StatusText.Text = "要約しています…";
        var ok = await _viewModel.SummarizeSelectedAsync(scope, _rallies);
        SummaryBox.Text = _viewModel.SummaryText;
        StatusText.Text = ok ? "要約しました。" : _viewModel.StatusMessage;
    }

    private void OnMemo(object sender, RoutedEventArgs e) => _navigator.ShowMemoForm(_session, memo: null);

    private void OnBack(object sender, RoutedEventArgs e) => _navigator.ShowList();
}
