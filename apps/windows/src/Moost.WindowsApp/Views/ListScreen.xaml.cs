using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Moost.Core;

namespace Moost.WindowsApp.Views;

/// <summary>
/// ルート画面（design.md 6.1 の list）。3 タブ（セッション / メモ / プロジェクト）を
/// セグメントピッカーで切り替え、行はタイトル・プロジェクト・日時・エージェントバッジ・
/// 行内ボタン（macOS 版と同じ並び）で描く。
/// </summary>
public partial class ListScreen : UserControl
{
    private readonly MainViewModel _viewModel;
    private readonly IAppNavigator _navigator;
    private readonly Action _quit;

    public ListScreen(MainViewModel viewModel, IAppNavigator navigator, Action quit)
    {
        _viewModel = viewModel;
        _navigator = navigator;
        _quit = quit;
        InitializeComponent();
        VersionText.Text = string.IsNullOrEmpty(_viewModel.AppVersion) ? string.Empty : $"v{_viewModel.AppVersion}";
        Reload();
    }

    /// <summary>ポップオーバー表示・タブ切替のたびに一覧を作り直す（design.md 6.1）。</summary>
    public void Reload()
    {
        _viewModel.Refresh();
        UpdateText.Text = _viewModel.UpdateText;
        UpdateButton.Visibility = _viewModel.UpdateText.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        RenderRows();
    }

    private void OnSegmentChanged(object sender, RoutedEventArgs e)
    {
        // XAML の IsChecked="True" は InitializeComponent の途中でも発火するため、
        // 部品が揃う前は何もしない（初期描画はコンストラクタの Reload が行う）
        if (RowsHost is null)
        {
            return;
        }

        RenderRows();
    }

    private void RenderRows()
    {
        RowsHost.Children.Clear();

        if (SessionsTab.IsChecked == true)
        {
            RenderSessions();
        }
        else if (MemosTab.IsChecked == true)
        {
            RenderMemos();
        }
        else
        {
            RenderProjects();
        }

        if (RowsHost.Children.Count == 0)
        {
            RowsHost.Children.Add(new TextBlock
            {
                Text = "まだありません。",
                Style = (Style)FindResource("AppCaptionText"),
                Margin = new Thickness(8, 16, 8, 0),
            });
        }
    }

    private void RenderSessions()
    {
        foreach (var session in _viewModel.Sessions)
        {
            var row = RowShell();

            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var titleLine = new DockPanel();
            titleLine.Children.Add(Badge(session.AgentId));
            var title = new TextBlock
            {
                Text = session.DisplayTitle,
                Style = (Style)FindResource("AppBodyText"),
                Margin = new Thickness(6, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            DockPanel.SetDock(title, Dock.Right);
            titleLine.Children.Add(title);
            texts.Children.Add(titleLine);
            texts.Children.Add(new TextBlock
            {
                Text = $"{session.ProjectPath} · {Local(session.UpdatedAt)}",
                Style = (Style)FindResource("AppCaptionText"),
                Margin = new Thickness(0, 2, 0, 0),
            });

            var buttons = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
            };
            buttons.Children.Add(IconButton("▶", "ターミナルで開く", () => Run(() => _viewModel.LaunchResume(session))));
            buttons.Children.Add(IconButton("ⓘ", "詳細", () => _navigator.ShowDetail(session)));
            buttons.Children.Add(IconButton("⧉", "復帰コマンドをコピー", () => Run(() => _viewModel.CopyResume(session))));

            Compose(row, texts, buttons);
            row.MouseLeftButtonUp += (_, _) => _navigator.ShowDetail(session);
            RowsHost.Children.Add(row);
        }
    }

    private void RenderMemos()
    {
        foreach (var memo in _viewModel.Memos)
        {
            var row = RowShell();

            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var titleLine = new DockPanel();
            titleLine.Children.Add(Badge(memo.Agent));
            var title = new TextBlock
            {
                Text = memo.Title,
                Style = (Style)FindResource("AppBodyText"),
                Margin = new Thickness(6, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            DockPanel.SetDock(title, Dock.Right);
            titleLine.Children.Add(title);
            texts.Children.Add(titleLine);
            texts.Children.Add(new TextBlock
            {
                Text = $"{memo.ProjectPath} · {Local(memo.UpdatedAt)}",
                Style = (Style)FindResource("AppCaptionText"),
                Margin = new Thickness(0, 2, 0, 0),
            });

            var buttons = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
            };
            buttons.Children.Add(IconButton("▶", "ターミナルで再開", () => Run(() =>
            {
                var session = new RecentSession
                {
                    AgentId = memo.Agent,
                    SessionId = memo.SessionId,
                    ProjectPath = memo.ProjectPath,
                    LastPrompt = memo.Body,
                    UpdatedAt = memo.UpdatedAt,
                };
                _viewModel.LaunchResume(session);
            })));
            buttons.Children.Add(IconButton("⧉", "復帰コマンドをコピー", () => Run(() =>
            {
                var session = new RecentSession
                {
                    AgentId = memo.Agent,
                    SessionId = memo.SessionId,
                    ProjectPath = memo.ProjectPath,
                    LastPrompt = memo.Body,
                    UpdatedAt = memo.UpdatedAt,
                };
                _viewModel.CopyResume(session);
            })));
            buttons.Children.Add(IconButton("🗑", "削除", () =>
            {
                _viewModel.DeleteMemo(memo.Id);
                Reload();
            }));
            buttons.Children.Add(IconButton("✎", "編集", () => _navigator.ShowMemoForm(session: null, memo: memo)));

            Compose(row, texts, buttons);
            row.MouseLeftButtonUp += (_, _) => _navigator.ShowMemoForm(session: null, memo: memo);
            RowsHost.Children.Add(row);
        }
    }

    private void RenderProjects()
    {
        foreach (var project in _viewModel.Projects)
        {
            var row = RowShell();

            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(new TextBlock
            {
                Text = project.DisplayName,
                Style = (Style)FindResource("AppBodyText"),
            });
            texts.Children.Add(new TextBlock
            {
                Text = $"{project.ProjectPath} · {Local(project.CreatedAt)}",
                Style = (Style)FindResource("AppCaptionText"),
                Margin = new Thickness(0, 2, 0, 0),
            });

            var buttons = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
            };
            foreach (var agent in new[] { "claude-code", "codex", "pi", "hermes" })
            {
                var agentId = agent;
                buttons.Children.Add(IconButton(
                    AgentVisual.ShortLabel(agentId),
                    $"{AgentVisual.DisplayName(agentId)} で新規セッション",
                    () => Run(() =>
                    {
                        var command = ResumeCommand.NewSession(agentId, project.ProjectPath,
                            _viewModel.Settings.PiProvider, _viewModel.Settings.PiModel);
                        if (command is not null)
                        {
                            new TerminalLauncher().Launch(command);
                        }
                    }),
                    AgentVisual.Color(agentId)));
            }

            buttons.Children.Add(IconButton("🗑", "削除", () =>
            {
                _viewModel.DeleteProject(project.Id);
                Reload();
            }));

            Compose(row, texts, buttons);
            RowsHost.Children.Add(row);
        }

        var addRow = RowShell();
        var pathBox = new TextBox
        {
            Style = (Style)FindResource("AppTextBox"),
            Margin = new Thickness(0, 0, 6, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        var addButton = new Button
        {
            Content = "フォルダを追加",
            Style = (Style)FindResource("AppSecondaryButton"),
            VerticalAlignment = VerticalAlignment.Center,
        };
        addButton.Click += (_, _) =>
        {
            _viewModel.NewProjectPath = pathBox.Text;
            if (_viewModel.AddProjectFromInput())
            {
                Reload();
            }
        };
        var addPanel = new DockPanel();
        DockPanel.SetDock(addButton, Dock.Right);
        addPanel.Children.Add(addButton);
        addPanel.Children.Add(pathBox);
        addRow.Child = addPanel;
        RowsHost.Children.Add(addRow);
    }

    // MARK: 部品

    private Border RowShell() => new()
    {
        CornerRadius = new CornerRadius(6),
        Background = (Brush)FindResource("SurfaceBrush"),
        BorderBrush = (Brush)FindResource("DividerBrush"),
        BorderThickness = new Thickness(1),
        Padding = new Thickness(8, 6, 8, 6),
        Margin = new Thickness(4, 0, 4, 6),
        Cursor = Cursors.Hand,
        Child = new Grid(),
    };

    private static void Compose(Border row, UIElement left, UIElement right)
    {
        var grid = (Grid)row.Child;
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn((UIElement)left, 0);
        Grid.SetColumn((UIElement)right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);
    }

    private Border Badge(string agentId) => new()
    {
        CornerRadius = new CornerRadius(7),
        Background = AgentVisual.Color(agentId),
        Padding = new Thickness(6, 1, 6, 1),
        VerticalAlignment = VerticalAlignment.Center,
        Child = new TextBlock
        {
            Text = AgentVisual.DisplayName(agentId),
            Foreground = Brushes.White,
            FontSize = 10,
            FontWeight = FontWeights.Medium,
        },
    };

    private Button IconButton(string glyph, string tooltip, Action onClick, Brush? foreground = null)
    {
        var button = new Button
        {
            Content = new TextBlock
            {
                Text = glyph,
                FontSize = 13,
                Foreground = foreground ?? (Brush)FindResource("SecondaryTextBrush"),
            },
            Style = (Style)FindResource("AppIconButton"),
            ToolTip = tooltip,
            Margin = new Thickness(2, 0, 0, 0),
        };
        button.Click += (_, eventArgs) =>
        {
            eventArgs.Handled = true;
            onClick();
        };
        return button;
    }

    /// <summary>行のクリックとボタンのクリックが二重に発火しないよう、ボタンは Handled にする。</summary>
    private void Run(Action action)
    {
        action();
        Reload();
    }

    private static string Local(DateTime value) => value.ToLocalTime().ToString("M/d HH:mm", System.Globalization.CultureInfo.CurrentCulture);

    private void OnSettings(object sender, RoutedEventArgs e) => _navigator.ShowSettings();

    private void OnNotes(object sender, RoutedEventArgs e) => _navigator.ShowNotes();

    private void OnQuit(object sender, RoutedEventArgs e) => _quit();

    private void OnUpdate(object sender, RoutedEventArgs e)
    {
        _viewModel.ApplyUpdateGuidance();
        Reload();
    }
}
