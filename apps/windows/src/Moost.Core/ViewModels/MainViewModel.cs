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
        Func<DateTime>? now = null)
    {
        _sources = sources;
        _memos = memos;
        _projects = projects;
        _settingsStore = settingsStore;
        _launcher = launcher;
        _copyToClipboard = copyToClipboard ?? (_ => { });
        _now = now ?? (() => DateTime.UtcNow);
        Settings = settingsStore.Load();
    }

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

    private void Notify([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
