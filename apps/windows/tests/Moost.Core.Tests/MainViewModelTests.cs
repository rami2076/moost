using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 画面の状態と操作（#103）。UI は WPF だが、ViewModel は UI 非依存なのでここで検証する。
/// </summary>
public class MainViewModelTests
{
    private static readonly DateTime Now = new(2026, 10, 25, 12, 0, 0, DateTimeKind.Utc);

    private static (MainViewModel ViewModel, TempDir Dir, List<string> Clipboard) Create(TempDir? dir = null)
    {
        var working = dir ?? new TempDir();
        var sources = new SessionSources
        {
            ClaudeHistoryFile = working.File("claude-history.jsonl"),
            ClaudeProjectsDirectory = Path.Combine(working.Path, "claude-projects"),
            CodexHistoryFile = working.File("codex-history.jsonl"),
            CodexSessionsDirectory = Path.Combine(working.Path, "codex-sessions"),
            PiSessionsDirectory = Path.Combine(working.Path, "pi-sessions"),
            HermesDatabase = working.File("state.db"),
        };

        // 直近セッション 1 件（claude）
        File.WriteAllLines(sources.ClaudeHistoryFile,
        [
            """{"display":"claude prompt","timestamp":1000,"project":"C:\\work\\alpha","sessionId":"S1"}""",
        ]);

        var clipboard = new List<string>();
        var viewModel = new MainViewModel(
            sources,
            new MemoStore(working.File("memos.json")),
            new ProjectStore(working.File("projects.json")),
            new SettingsStore(working.File("settings.json")),
            new TerminalLauncher(executableExists: _ => false, start: _ => true),
            copyToClipboard: clipboard.Add,
            now: () => Now);

        viewModel.Refresh();
        return (viewModel, working, clipboard);
    }

    [Fact]
    public void Refresh_LoadsSessionsMemosProjectsAndSettings()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);

        var session = Assert.Single(viewModel.Sessions);
        Assert.Equal("S1", session.SessionId);
        Assert.Equal(ResumeCommand.ClaudeAgentId, session.AgentId);
        Assert.Empty(viewModel.Memos);
        Assert.Empty(viewModel.Projects);
        Assert.Equal(Settings.Default, viewModel.Settings);
    }

    [Fact]
    public void CopyResume_PutsThePowerShellCommandOnTheClipboard()
    {
        using var dir = new TempDir();
        var (viewModel, _, clipboard) = Create(dir);
        var session = viewModel.Sessions[0];

        Assert.True(viewModel.CopyResume(session));

        var command = Assert.Single(clipboard);
        Assert.StartsWith("Set-Location -LiteralPath 'C:\\work\\alpha'; ", command, StringComparison.Ordinal);
        Assert.Contains("claude --resume 'S1'", command, StringComparison.Ordinal);
        Assert.Contains("コピー", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void LaunchResume_UsesTheTerminalLauncher()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);

        Assert.True(viewModel.LaunchResume(viewModel.Sessions[0]));
        Assert.Contains("ターミナル", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void LaunchResume_ReportsFailureInStatus()
    {
        using var dir = new TempDir();
        var (_, working, _) = Create(dir);
        var failing = new MainViewModel(
            new SessionSources
            {
                ClaudeHistoryFile = working.File("claude-history.jsonl"),
                ClaudeProjectsDirectory = Path.Combine(working.Path, "p"),
                CodexHistoryFile = working.File("c"),
                CodexSessionsDirectory = Path.Combine(working.Path, "cs"),
                PiSessionsDirectory = Path.Combine(working.Path, "ps"),
                HermesDatabase = working.File("state.db"),
            },
            new MemoStore(working.File("memos.json")),
            new ProjectStore(working.File("projects.json")),
            new SettingsStore(working.File("settings.json")),
            new TerminalLauncher(executableExists: _ => false, start: _ => false));
        failing.Refresh();

        Assert.False(failing.LaunchResume(failing.Sessions[0]));
        Assert.Contains("起動できませんでした", failing.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void CreateMemoFromSession_CapturesSessionIdentity()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        var session = viewModel.Sessions[0];

        var memo = viewModel.CreateMemoFromSession(session, "表題", "auth, wip", "本文");

        Assert.Equal(ResumeCommand.ClaudeAgentId, memo.Agent);
        Assert.Equal("S1", memo.SessionId);
        Assert.Equal("C:\\work\\alpha", memo.ProjectPath);
        Assert.Equal(["auth", "wip"], memo.Tags);
        Assert.Equal(Now, memo.CreatedAt);
        Assert.Single(viewModel.Memos);
    }

    [Fact]
    public void UpdateMemo_ChangesOnlyUserFields()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        var memo = viewModel.CreateMemoFromSession(viewModel.Sessions[0], "旧", "a", "旧本文");

        Assert.True(viewModel.UpdateMemo(memo.Id, "新", "b, c", "新本文"));

        var updated = Assert.Single(viewModel.Memos);
        Assert.Equal("新", updated.Title);
        Assert.Equal(["b", "c"], updated.Tags);
        Assert.Equal("新本文", updated.Body);
        // 不変フィールドは動かない
        Assert.Equal(memo.SessionId, updated.SessionId);
        Assert.Equal(memo.CreatedAt, updated.CreatedAt);
    }

    [Fact]
    public void DeleteMemo_RemovesIt()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        var memo = viewModel.CreateMemoFromSession(viewModel.Sessions[0], "t", "", "");

        Assert.True(viewModel.DeleteMemo(memo.Id));
        Assert.Empty(viewModel.Memos);
        Assert.False(viewModel.DeleteMemo(memo.Id));
    }

    [Fact]
    public void AddProject_UsesDisplayNameDerivation()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);

        var project = viewModel.AddProject("C:\\work\\new-project");

        Assert.Equal("new-project", project.DisplayName);
        Assert.Single(viewModel.Projects);
    }

    [Fact]
    public void SaveSettings_PersistsAndRefreshes()
    {
        using var dir = new TempDir();
        var (viewModel, working, _) = Create(dir);

        viewModel.SaveSettings(Settings.Default with { TerminalApp = "wt.exe", RecentSessionLimit = 5 });

        Assert.Equal("wt.exe", viewModel.Settings.TerminalApp);
        Assert.Equal("wt.exe", new SettingsStore(working.File("settings.json")).Load().TerminalApp);
    }

    [Fact]
    public void ResumeCommandFor_UsesPiProviderAndModelFromSettings()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        viewModel.SaveSettings(Settings.Default with { PiProvider = "dspark", PiModel = "qwen3" });

        var command = ResumeCommandFor(viewModel, "pi", "C:\\w", "p-1");

        Assert.NotNull(command);
        Assert.Contains("pi --session 'p-1'", command, StringComparison.Ordinal);
        Assert.Contains("--provider 'dspark'", command, StringComparison.Ordinal);
        Assert.Contains("--model 'qwen3'", command, StringComparison.Ordinal);
    }

    [Fact]
    public void UnknownAgent_IsReportedInsteadOfCrashing()
    {
        using var dir = new TempDir();
        var (viewModel, _, clipboard) = Create(dir);
        var bogus = new RecentSession
        {
            AgentId = "gemini",
            SessionId = "g1",
            ProjectPath = "/w",
            LastPrompt = "p",
            UpdatedAt = Now,
        };

        Assert.False(viewModel.CopyResume(bogus));
        Assert.Empty(clipboard);
        Assert.Contains("不明なエージェント", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    private static string? ResumeCommandFor(MainViewModel viewModel, string agent, string project, string session)
    {
        var sessionLike = new RecentSession
        {
            AgentId = agent,
            SessionId = session,
            ProjectPath = project,
            LastPrompt = "p",
            UpdatedAt = Now,
        };
        return viewModel.ResumeCommandFor(sessionLike);
    }
}
