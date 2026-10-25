using System.IO;
using System.Windows;
using System.Windows.Controls;
using Moost.Core;

namespace Moost.WindowsApp;

/// <summary>
/// 画面一式（#103）。ViewModel（Moost.Core）の状態を表示し、操作を委譲するだけの薄い View。
///
/// 画面: セッション一覧 / メモ / プロジェクト / 詳細（要約）/ 設定 / 注意。
/// バインドは最小限にし、値の受け渡しはコードビハインドで行う（XAML の取り違えを避ける）。
/// </summary>
public partial class PopoverWindow : Window
{
    private readonly MainViewModel _viewModel;

    public PopoverWindow(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();

        VersionText.Text = string.IsNullOrEmpty(_viewModel.AppVersion) ? string.Empty : $"v{_viewModel.AppVersion}";
        NoticeBlock.Text = MainViewModel.NoticeText;
        RefreshAll();
    }

    /// <summary>トレイから表示されるたびに呼ぶ（一覧の再読込・design.md 6.1）。</summary>
    public void RefreshAll()
    {
        _viewModel.Refresh();
        _viewModel.RefreshAutoStart();

        SessionList.ItemsSource = _viewModel.Sessions;
        MemoList.ItemsSource = _viewModel.Memos;
        ProjectList.ItemsSource = _viewModel.Projects;

        var settings = _viewModel.Settings;
        TerminalAppBox.Text = settings.TerminalApp;
        LimitBox.Text = settings.RecentSessionLimit.ToString(System.Globalization.CultureInfo.InvariantCulture);
        ClaudePathBox.Text = settings.ClaudePath;
        RallyBox.Text = settings.SummaryRallyCount.ToString(System.Globalization.CultureInfo.InvariantCulture);
        CopyAnimationBox.IsChecked = settings.CopyAnimation;
        AutoStartBox.IsChecked = _viewModel.AutoStartEnabled;

        StatusText.Text = _viewModel.StatusMessage;

        UpdateText.Text = _viewModel.UpdateText;
        UpdateButton.Visibility = _viewModel.UpdateText.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: セッション

    private void OnSessionSelected(object sender, SelectionChangedEventArgs e)
    {
        if (SessionList.SelectedItem is RecentSession session)
        {
            _viewModel.SelectSessionForMemo(session);
            DetailTitle.Text = $"{session.DisplayTitle}（{session.AgentId}）\n{session.ProjectPath}";
            SummaryBox.Text = _viewModel.SummaryText;
        }
    }

    private void OnCopyResume(object sender, RoutedEventArgs e)
    {
        if (CurrentSession() is { } session)
        {
            _viewModel.CopyResume(session);
            StatusText.Text = _viewModel.StatusMessage;
        }
    }

    private void OnLaunchResume(object sender, RoutedEventArgs e)
    {
        if (CurrentSession() is { } session)
        {
            _viewModel.LaunchResume(session);
            StatusText.Text = _viewModel.StatusMessage;
        }
    }

    private void OnMemoFromSession(object sender, RoutedEventArgs e)
    {
        if (CurrentSession() is not { } session)
        {
            return;
        }

        _viewModel.SelectSessionForMemo(session);
        MemoTitleBox.Text = _viewModel.MemoTitle;
        MemoTagsBox.Text = _viewModel.MemoTags;
        MemoBodyBox.Text = _viewModel.MemoBody;
        StatusText.Text = "メモの内容を入力して「登録 / 更新」を押してください。";
    }

    // MARK: メモ

    private void OnMemoSelected(object sender, SelectionChangedEventArgs e)
    {
        if (MemoList.SelectedItem is Memo memo)
        {
            MemoTitleBox.Text = memo.Title;
            MemoTagsBox.Text = string.Join(", ", memo.Tags);
            MemoBodyBox.Text = memo.Body;
        }
    }

    private void OnSaveMemo(object sender, RoutedEventArgs e)
    {
        // 一覧で選択中のメモがあれば更新、無ければセッションから新規登録
        if (MemoList.SelectedItem is Memo selected)
        {
            _viewModel.UpdateMemo(selected.Id, MemoTitleBox.Text, MemoTagsBox.Text, MemoBodyBox.Text);
        }
        else
        {
            _viewModel.MemoTitle = MemoTitleBox.Text;
            _viewModel.MemoTags = MemoTagsBox.Text;
            _viewModel.MemoBody = MemoBodyBox.Text;
            _viewModel.SaveMemoFromForm();
        }

        RefreshLists();
        StatusText.Text = _viewModel.StatusMessage;
    }

    private void OnDeleteMemo(object sender, RoutedEventArgs e)
    {
        if (MemoList.SelectedItem is Memo memo)
        {
            _viewModel.DeleteMemo(memo.Id);
            RefreshLists();
            StatusText.Text = _viewModel.StatusMessage;
        }
    }

    // MARK: プロジェクト

    private void OnAddProject(object sender, RoutedEventArgs e)
    {
        _viewModel.NewProjectPath = ProjectPathBox.Text;
        if (_viewModel.AddProjectFromInput())
        {
            ProjectPathBox.Text = string.Empty;
        }

        RefreshLists();
        StatusText.Text = _viewModel.StatusMessage;
    }

    // MARK: 要約

    private async void OnSummarizeRecent(object sender, RoutedEventArgs e) => await SummarizeAsync(SummaryScope.Recent);

    private async void OnSummarizeFull(object sender, RoutedEventArgs e) => await SummarizeAsync(SummaryScope.Full);

    private async Task SummarizeAsync(SummaryScope scope)
    {
        if (SessionList.SelectedItem is not RecentSession)
        {
            StatusText.Text = "先にセッションを選んでください。";
            return;
        }

        StatusText.Text = "要約しています…";
        await _viewModel.SummarizeSelectedAsync(scope, rallies: _viewModel.Settings.SummaryRallyCount);
        SummaryBox.Text = _viewModel.SummaryText;
        StatusText.Text = _viewModel.StatusMessage;
    }

    // MARK: 設定

    private void OnSaveSettings(object sender, RoutedEventArgs e)
    {
        var settings = _viewModel.Settings with
        {
            TerminalApp = TerminalAppBox.Text,
            RecentSessionLimit = ParseInt(LimitBox.Text, 20, 5, 100),
            ClaudePath = ClaudePathBox.Text,
            SummaryRallyCount = ParseInt(RallyBox.Text, 1, 1, 20),
            CopyAnimation = CopyAnimationBox.IsChecked == true,
        };

        _viewModel.SaveSettings(settings);

        // 自動起動は OS の実状態を正とするため、設定保存とは別に扱う（C4）
        var executable = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "Moost.exe");
        _viewModel.SetAutoStart(AutoStartBox.IsChecked == true, executable);

        RefreshAll();
        StatusText.Text = _viewModel.StatusMessage;
    }

    private static int ParseInt(string text, int fallback, int min, int max)
    {
        if (!int.TryParse(text, System.Globalization.NumberStyles.Integer,
                System.Globalization.CultureInfo.InvariantCulture, out var value))
        {
            return fallback;
        }

        return Math.Clamp(value, min, max);
    }

    private async void OnApplyUpdate(object sender, RoutedEventArgs e)
    {
        _viewModel.ApplyUpdateGuidance();
        StatusText.Text = _viewModel.StatusMessage;
    }

    /// <summary>更新チェック（方式 7）。失敗しても沈黙する。</summary>
    public async Task CheckForUpdatesAsync()
    {
        await _viewModel.CheckForUpdatesAsync();
        UpdateText.Text = _viewModel.UpdateText;
        UpdateButton.Visibility = _viewModel.UpdateText.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnTabChanged(object sender, SelectionChangedEventArgs e)
    {
        // タブを切り替えたら表示を最新にする（古い一覧を見せない）
        RefreshLists();
    }

    private void RefreshLists()
    {
        SessionList.ItemsSource = _viewModel.Sessions;
        MemoList.ItemsSource = _viewModel.Memos;
        ProjectList.ItemsSource = _viewModel.Projects;
    }

    private RecentSession? CurrentSession() =>
        SessionList.SelectedItem as RecentSession ?? _viewModel.SelectedSession;
}
