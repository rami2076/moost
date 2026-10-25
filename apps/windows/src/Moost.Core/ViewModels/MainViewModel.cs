using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Moost.Core;

/// <summary>
/// 画面の状態と操作（UI 非依存・#103）。WPF の View はこれにバインドする。
///
/// ロジックはすべて <c>Moost.Core</c> のサービスに委譲し、このクラスは
/// 「表示用の状態を持つ」「操作の順序を決める」ことだけを担う（テスト可能）。
/// </summary>
public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly SessionSources _sources;
    private readonly MemoStore _memos;
    private readonly ProjectStore _projects;
    private readonly SettingsStore _settingsStore;
    private readonly TerminalLauncher _launcher;
    private readonly Action<string> _copyToClipboard;
    private readonly Func<DateTime> _now;

    public MainViewModel(
        SessionSources sources,
        MemoStore memos,
        ProjectStore projects,
        SettingsStore settingsStore,
        TerminalLauncher launcher,
        Action<string>? copyToClipboard = null,
        Func<DateTime>? now = null,
        AutoStartService? autoStart = null,
        string appVersion = "",
        UpdateChecker? updateChecker = null,
        string? processPath = null,
        Action<string>? openUrl = null)
    {
        _sources = sources;
        _memos = memos;
        _projects = projects;
        _settingsStore = settingsStore;
        _launcher = launcher;
        _copyToClipboard = copyToClipboard ?? (_ => { });
        _now = now ?? (() => DateTime.UtcNow);
        _autoStart = autoStart;
        _updateChecker = updateChecker;
        _openUrl = openUrl ?? (_ => { });
        _processPath = processPath ?? Environment.ProcessPath;
        AppVersion = appVersion;
        Settings = settingsStore.Load();
        RefreshAutoStart();
    }

    private readonly AutoStartService? _autoStart;
    private readonly UpdateChecker? _updateChecker;
    private readonly Action<string> _openUrl;
    private readonly string? _processPath;
    private string? _availableUpdateUrl;

    /// <summary>フッターの更新通知（空なら表示しない・方式 7）。</summary>
    public string UpdateText { get; private set; } = string.Empty;

    /// <summary>更新導線のコマンド（winget 管理下のときのみ。null ならリリースページを開く）。</summary>
    public string? AvailableUpdateCommand { get; private set; }

    /// <summary>設定画面に表示するアプリのバージョン（ビルド時にタグから注入される）。</summary>
    public string AppVersion { get; }

    /// <summary>要約の結果（永続化しない・ADR-002）。</summary>
    public string SummaryText { get; private set; } = string.Empty;

    /// <summary>選択中のセッション（メモフォームの初期値に使う）。</summary>
    public RecentSession? SelectedSession { get; set; }

    /// <summary>メモフォームの入力値。</summary>
    public string MemoTitle { get; set; } = string.Empty;

    public string MemoTags { get; set; } = string.Empty;

    public string MemoBody { get; set; } = string.Empty;

    /// <summary>登録プロジェクトの入力値。</summary>
    public string NewProjectPath { get; set; } = string.Empty;

    /// <summary>ログイン時自動起動の実状態（OS のレジストリを正とする・C4）。</summary>
    public bool AutoStartEnabled { get; private set; }

    /// <summary>注意画面の文言（requirements 3.5・3.6）。</summary>
    public const string NoticeText =
        "・要約は AI の利用枠（API）を消費します。モデルは haiku 固定です。\n" +
        "・要約は保存されません（アプリを終了すると消えます）。残したい要点はメモに書き移してください。\n" +
        "・セッションは Claude Code の cleanupPeriodDays（既定 30 日）で自動削除されます。" +
        "期限切れのセッションには復帰できません。\n" +
        "・エージェント側のデータには書き込みません（読み取り専用）。";

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>直近セッション（新しい順）。</summary>
    public IReadOnlyList<RecentSession> Sessions { get; private set; } = [];

    /// <summary>メモ一覧（保存順）。</summary>
    public IReadOnlyList<Memo> Memos { get; private set; } = [];

    /// <summary>登録プロジェクト。</summary>
    public IReadOnlyList<Project> Projects { get; private set; } = [];

    /// <summary>アプリ設定。</summary>
    public Settings Settings { get; private set; }

    /// <summary>画面下部のステータス（コピー成功・エラー等）。</summary>
    public string StatusMessage { get; private set; } = string.Empty;

    /// <summary>処理中か（要約の実行中など）。</summary>
    public bool IsBusy { get; private set; }

    /// <summary>一覧・メモ・プロジェクト・設定を読み直す（ポップオーバー表示のたび）。</summary>
    public void Refresh()
    {
        Sessions = SessionAggregator.RecentSessions(_sources, Settings.RecentSessionLimit);
        Memos = _memos.Load();
        Projects = _projects.Load();
        Settings = _settingsStore.Load();
        Notify(nameof(Sessions));
        Notify(nameof(Memos));
        Notify(nameof(Projects));
        Notify(nameof(Settings));
    }

    /// <summary>セッションの復帰コマンド（不明なエージェントなら null）。</summary>
    public string? ResumeCommandFor(RecentSession session) =>
        ResumeCommand.Resume(
            session.AgentId,
            session.ProjectPath,
            session.SessionId,
            Settings.PiProvider,
            Settings.PiModel);

    /// <summary>復帰コマンドをクリップボードへコピーする。</summary>
    public bool CopyResume(RecentSession session)
    {
        var command = ResumeCommandFor(session);
        if (command is null)
        {
            SetStatus("不明なエージェントです。");
            return false;
        }

        _copyToClipboard(command);
        SetStatus("復帰コマンドをコピーしました。");
        return true;
    }

    /// <summary>復帰コマンドを端末で実行する（新しいウィンドウ/タブで開く）。</summary>
    public bool LaunchResume(RecentSession session)
    {
        var command = ResumeCommandFor(session);
        if (command is null)
        {
            SetStatus("不明なエージェントです。");
            return false;
        }

        try
        {
            _launcher.Launch(command);
            SetStatus("ターミナルで開きました。");
            return true;
        }
        catch (TerminalLaunchException exception)
        {
            SetStatus(exception.Message);
            return false;
        }
    }

    /// <summary>セッションからメモを作る（sessionId / projectPath / agent を自己完結で捕捉・ADR-003）。</summary>
    public Memo CreateMemoFromSession(RecentSession session, string title, string tags, string body)
    {
        var now = _now();
        var memo = new Memo
        {
            Id = Guid.NewGuid().ToString(),
            Agent = session.AgentId,
            SessionId = session.SessionId,
            Title = title,
            Tags = Memo.ParseTags(tags),
            Body = body,
            ProjectPath = session.ProjectPath,
            CreatedAt = now,
            UpdatedAt = now,
        };

        _memos.Add(memo);
        Refresh();
        SetStatus("メモを登録しました。");
        return memo;
    }

    /// <summary>メモの可変フィールド（title / tags / body）を更新する。</summary>
    public bool UpdateMemo(string id, string title, string tags, string body)
    {
        var updated = _memos.Update(id, title: title, tags: Memo.ParseTags(tags), body: body, updatedAt: _now());
        Refresh();
        SetStatus(updated ? "メモを更新しました。" : "メモが見つかりません。");
        return updated;
    }

    public bool DeleteMemo(string id)
    {
        var deleted = _memos.Delete(id);
        Refresh();
        SetStatus(deleted ? "メモを削除しました。" : "メモが見つかりません。");
        return deleted;
    }

    /// <summary>登録プロジェクトを追加する（セッションが無いディレクトリでも登録できる・ADR-004）。</summary>
    public Project AddProject(string projectPath)
    {
        var project = new Project
        {
            Id = Guid.NewGuid().ToString(),
            ProjectPath = projectPath,
            CreatedAt = _now(),
        };

        _projects.Add(project);
        Refresh();
        SetStatus("プロジェクトを登録しました。");
        return project;
    }

    public bool DeleteProject(string id)
    {
        var deleted = _projects.Delete(id);
        Refresh();
        SetStatus(deleted ? "プロジェクトを削除しました。" : "プロジェクトが見つかりません。");
        return deleted;
    }

    /// <summary>設定を保存する（ログイン時起動は設定に含めない・C4）。</summary>
    public void SaveSettings(Settings settings)
    {
        _settingsStore.Save(settings);
        Settings = settings;
        Notify(nameof(Settings));
        SetStatus("設定を保存しました。");
    }

    /// <summary>要約を実行する（pi / hermes はローカル抽出＝API 消費ゼロ）。</summary>
    public async Task<string> SummarizeAsync(
        RecentSession session,
        SummaryScope scope,
        int rallies = 1,
        SessionSummarizer? summarizer = null,
        CancellationToken cancellationToken = default)
    {
        var service = summarizer ?? new SessionSummarizer(
            _sources,
            // 要約用 CLI の解決（設定の上書き → 既知パス → PATH）
            command => command switch
            {
                "claude" => AgentPathDetect.Claude(Settings.ClaudePath),
                "codex" => AgentPathDetect.Codex(),
                _ => AgentPathDetect.FromPath(command),
            },
            TimeSpan.FromMinutes(3));

        IsBusy = true;
        Notify(nameof(IsBusy));
        try
        {
            var summary = await service
                .SummarizeAsync(session.AgentId, session.SessionId, scope, rallies, session.ProjectPath, cancellationToken)
                .ConfigureAwait(false);
            SetStatus("要約しました。");
            return summary;
        }
        catch (SummarizeException exception)
        {
            SetStatus(exception.Message);
            throw;
        }
        finally
        {
            IsBusy = false;
            Notify(nameof(IsBusy));
        }
    }

    private void SetStatus(string message)
    {
        StatusMessage = message;
        Notify(nameof(StatusMessage));
    }

    /// <summary>
    /// 更新を確認する（方式 7・失敗は沈默・5 分の間引き）。起動時とポップオーバー表示時に呼ぶ。
    /// </summary>
    public async Task CheckForUpdatesAsync(CancellationToken cancellationToken = default)
    {
        if (_updateChecker is null)
        {
            return;
        }

        var update = await _updateChecker.CheckAsync(cancellationToken).ConfigureAwait(false);
        if (update is null)
        {
            UpdateText = string.Empty;
            AvailableUpdateCommand = null;
            _availableUpdateUrl = null;
        }
        else
        {
            UpdateText = $"v{update.Semver} が利用可能です";
            AvailableUpdateCommand = UpdateGuidance.CommandFor(_processPath);
            _availableUpdateUrl = update.Url;
        }

        Notify(nameof(UpdateText));
        Notify(nameof(AvailableUpdateCommand));
    }

    /// <summary>
    /// 更新導線を実行する: winget 管理下ならコマンドをコピー、そうでなければリリースページを開く。
    /// </summary>
    public bool ApplyUpdateGuidance()
    {
        if (AvailableUpdateCommand is { } command)
        {
            _copyToClipboard(command);
            SetStatus("更新コマンドをコピーしました。");
            return true;
        }

        if (_availableUpdateUrl is { } url)
        {
            _openUrl(url);
            SetStatus("リリースページを開きました。");
            return true;
        }

        return false;
    }

    /// <summary>セッションを選んでメモフォームの初期値を埋める（ADR-003 の自己完結捕捉）。</summary>
    public void SelectSessionForMemo(RecentSession session)
    {
        SelectedSession = session;
        MemoTitle = session.DisplayTitle;
        MemoTags = string.Empty;
        MemoBody = string.Empty;
        Notify(nameof(SelectedSession));
        Notify(nameof(MemoTitle));
        Notify(nameof(MemoTags));
        Notify(nameof(MemoBody));
    }

    /// <summary>フォームの内容でメモを登録する（セッション未選択なら null）。</summary>
    public Memo? SaveMemoFromForm()
    {
        if (SelectedSession is not { } session)
        {
            SetStatus("先にセッションを選んでください。");
            return null;
        }

        return CreateMemoFromSession(session, MemoTitle, MemoTags, MemoBody);
    }

    /// <summary>入力されたパスを登録プロジェクトに追加する（空ならエラー表示）。</summary>
    public bool AddProjectFromInput()
    {
        if (string.IsNullOrWhiteSpace(NewProjectPath))
        {
            SetStatus("パスを入力してください。");
            return false;
        }

        AddProject(NewProjectPath.Trim());
        NewProjectPath = string.Empty;
        Notify(nameof(NewProjectPath));
        return true;
    }

    /// <summary>自動起動の実状態を読み直す（画面表示のたび）。</summary>
    public void RefreshAutoStart()
    {
        // レジストリは Windows 専用（他 OS では常に false）
        AutoStartEnabled = OperatingSystem.IsWindows() && (_autoStart?.IsEnabled() ?? false);
        Notify(nameof(AutoStartEnabled));
    }

    /// <summary>自動起動を切り替える（OS の実状態を書き換える・C4）。</summary>
    public bool SetAutoStart(bool enabled, string executablePath)
    {
        if (_autoStart is null || !OperatingSystem.IsWindows())
        {
            SetStatus("自動起動はこの環境では利用できません。");
            return false;
        }

        try
        {
            if (enabled)
            {
                _autoStart.Enable(executablePath);
            }
            else
            {
                _autoStart.Disable();
            }

            RefreshAutoStart();
            SetStatus(enabled ? "自動起動を有効にしました。" : "自動起動を解除しました。");
            return true;
        }
        catch (Exception exception) when (exception is InvalidOperationException or UnauthorizedAccessException)
        {
            SetStatus($"自動起動を変更できませんでした: {exception.Message}");
            return false;
        }
    }

    /// <summary>選択中セッションの要約を実行して保持する（永続化しない・ADR-002）。</summary>
    public async Task<bool> SummarizeSelectedAsync(
        SummaryScope scope,
        int rallies = 1,
        SessionSummarizer? summarizer = null,
        CancellationToken cancellationToken = default)
    {
        if (SelectedSession is not { } session)
        {
            SetStatus("先にセッションを選んでください。");
            return false;
        }

        try
        {
            SummaryText = await SummarizeAsync(session, scope, rallies, summarizer, cancellationToken)
                .ConfigureAwait(false);
            Notify(nameof(SummaryText));
            return true;
        }
        catch (SummarizeException)
        {
            // ステータスに理由を出しているのでここでは握りつぶす（UI を止めない）
            return false;
        }
    }

    private void Notify([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
