using System.Windows;
using System.Windows.Controls;
using Moost.Core;

namespace Moost.WindowsApp.Views;

/// <summary>メモ登録・編集フォーム（design.md 6.1 の newMemo / editMemo）。</summary>
public partial class MemoFormScreen : UserControl
{
    private readonly MainViewModel _viewModel;
    private readonly IAppNavigator _navigator;
    private readonly RecentSession? _session;
    private readonly Memo? _memo;

    public MemoFormScreen(MainViewModel viewModel, IAppNavigator navigator, RecentSession? session, Memo? memo)
    {
        _viewModel = viewModel;
        _navigator = navigator;
        _session = session;
        _memo = memo;
        InitializeComponent();

        if (memo is not null)
        {
            TitleText.Text = "メモを編集";
            SessionText.Text = $"{memo.SessionId} · {memo.ProjectPath}";
            TitleBox.Text = memo.Title;
            TagsBox.Text = string.Join(", ", memo.Tags);
            BodyBox.Text = memo.Body;
        }
        else if (session is not null)
        {
            TitleText.Text = "メモを登録";
            SessionText.Text = $"{session.DisplayTitle} · {session.ProjectPath}";
            TitleBox.Text = session.DisplayTitle;
        }
        else
        {
            TitleText.Text = "メモを登録";
        }

        TitleBox.Focus();
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        if (_memo is not null)
        {
            _viewModel.UpdateMemo(_memo.Id, TitleBox.Text, TagsBox.Text, BodyBox.Text);
        }
        else if (_session is not null)
        {
            _viewModel.CreateMemoFromSession(_session, TitleBox.Text, TagsBox.Text, BodyBox.Text);
        }
        else
        {
            StatusText.Text = "対象のセッションがありません。";
            return;
        }

        _navigator.ShowList();
    }

    private void OnBack(object sender, RoutedEventArgs e) => _navigator.ShowList();
}
