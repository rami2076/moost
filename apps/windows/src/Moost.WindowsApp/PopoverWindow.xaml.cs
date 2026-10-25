using System.Windows;
using System.Windows.Controls;
using Moost.Core;
using Moost.WindowsApp.Views;

namespace Moost.WindowsApp;

/// <summary>
/// ポップオーバー相当のウィンドウ（design.md 6 章）。中身は**単一画面のステートマシン**（6.1）で、
/// このクラスが画面の差し替え（遷移）を担う。スタック型ナビゲーションは使わない。
/// </summary>
public partial class PopoverWindow : Window, IAppNavigator
{
    private readonly MainViewModel _viewModel;
    private readonly Action _quit;
    private ListScreen? _list;

    public PopoverWindow(MainViewModel viewModel, Action quit)
    {
        _viewModel = viewModel;
        _quit = quit;
        InitializeComponent();
        ShowList();
    }

    /// <summary>トレイから表示されるたびに呼ぶ（一覧の再読込・design.md 6.1）。</summary>
    public void RefreshAll()
    {
        _viewModel.Refresh();
        _viewModel.RefreshAutoStart();
        if (ScreenHost.Content is ListScreen list)
        {
            list.Reload();
        }
        else
        {
            ShowList();
        }
    }

    /// <summary>更新チェック（方式 7・失敗は沈黙）。</summary>
    public async Task CheckForUpdatesAsync()
    {
        await _viewModel.CheckForUpdatesAsync();
        if (ScreenHost.Content is ListScreen list)
        {
            list.Reload();
        }
    }

    public void ShowList()
    {
        _list = new ListScreen(_viewModel, this, _quit);
        ScreenHost.Content = _list;
    }

    public void ShowMemoForm(RecentSession? session, Memo? memo) =>
        ScreenHost.Content = new MemoFormScreen(_viewModel, this, session, memo);

    public void ShowDetail(RecentSession session) =>
        ScreenHost.Content = new SessionDetailScreen(_viewModel, this, session);

    public void ShowSettings() =>
        ScreenHost.Content = new SettingsScreen(_viewModel, this);

    public void ShowNotes() =>
        ScreenHost.Content = new NotesScreen(this);
}
