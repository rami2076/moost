using System.Net.Http;
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

    [Fact]
    public void SelectSessionForMemo_FillsTitleFromDisplayTitle()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        var session = viewModel.Sessions[0];

        viewModel.SelectSessionForMemo(session);

        Assert.Same(session, viewModel.SelectedSession);
        Assert.Equal(session.DisplayTitle, viewModel.MemoTitle);
        Assert.Equal(string.Empty, viewModel.MemoTags);
        Assert.Equal(string.Empty, viewModel.MemoBody);
    }

    [Fact]
    public void SaveMemoFromForm_RequiresASelectedSession()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);

        Assert.Null(viewModel.SaveMemoFromForm());
        Assert.Contains("セッションを選んで", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void SaveMemoFromForm_UsesTheFormValues()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        viewModel.SelectSessionForMemo(viewModel.Sessions[0]);
        viewModel.MemoTitle = "フォームの表題";
        viewModel.MemoTags = "a, b";
        viewModel.MemoBody = "フォームの本文";

        var memo = viewModel.SaveMemoFromForm();

        Assert.NotNull(memo);
        Assert.Equal("フォームの表題", memo!.Title);
        Assert.Equal(["a", "b"], memo.Tags);
        Assert.Equal("フォームの本文", memo.Body);
        Assert.Equal("S1", memo.SessionId);
    }

    [Fact]
    public void AddProjectFromInput_TrimsAndClearsTheInput()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        viewModel.NewProjectPath = @"  C:\work\trimmed  ";

        Assert.True(viewModel.AddProjectFromInput());
        Assert.Equal(string.Empty, viewModel.NewProjectPath);
        Assert.Equal("trimmed", viewModel.Projects[0].DisplayName);
    }

    [Fact]
    public void AddProjectFromInput_RejectsEmptyInput()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);
        viewModel.NewProjectPath = "   ";

        Assert.False(viewModel.AddProjectFromInput());
        Assert.Empty(viewModel.Projects);
    }

    [Fact]
    public void AutoStart_IsUnavailableWithoutTheService()
    {
        using var dir = new TempDir();
        var (viewModel, _, _) = Create(dir);

        Assert.False(viewModel.AutoStartEnabled);
        Assert.False(viewModel.SetAutoStart(true, @"C:\Moost\Moost.exe"));
        Assert.Contains("利用できません", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void NoticeText_CoversExpiryAndReadOnly()
    {
        Assert.Contains("cleanupPeriodDays", MainViewModel.NoticeText, StringComparison.Ordinal);
        Assert.Contains("読み取り専用", MainViewModel.NoticeText, StringComparison.Ordinal);
        Assert.Contains("保存されません", MainViewModel.NoticeText, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CheckForUpdates_ShowsAvailableVersion_AndCopiesWingetCommand()
    {
        using var dir = new TempDir();
        var handler = new StubUpdateHandler("v9.9.9-windows");
        var checker = new UpdateChecker("1.0.0", new HttpClient(handler));
        var clipboard = new List<string>();
        var viewModel = BuildViewModel(dir, checker, clipboard, opened: null, processPath: @"C:\Users\me\AppData\Local\Microsoft\WinGet\Packages\rami2076.Moost_1.0.0_x64__abc\Moost.exe");

        await viewModel.CheckForUpdatesAsync();

        Assert.Contains("9.9.9", viewModel.UpdateText, StringComparison.Ordinal);
        Assert.NotNull(viewModel.AvailableUpdateCommand);

        Assert.True(viewModel.ApplyUpdateGuidance());
        Assert.Contains("winget upgrade", Assert.Single(clipboard), StringComparison.Ordinal);
    }

    [Fact]
    public async Task CheckForUpdates_OpensReleasePage_ForManualInstall()
    {
        using var dir = new TempDir();
        var handler = new StubUpdateHandler("v9.9.9-windows");
        var checker = new UpdateChecker("1.0.0", new HttpClient(handler));
        var opened = new List<string>();
        var viewModel = BuildViewModel(dir, checker, clipboard: null, opened: opened, processPath: @"C:\Users\me\AppData\Local\Programs\Moost\Moost.exe");

        await viewModel.CheckForUpdatesAsync();
        Assert.True(viewModel.ApplyUpdateGuidance());

        Assert.Single(opened);
        Assert.Contains("/releases/tag/v9.9.9-windows", opened[0], StringComparison.Ordinal);
    }

    [Fact]
    public async Task CheckForUpdates_IsSilent_WhenNothingNew()
    {
        using var dir = new TempDir();
        var checker = new UpdateChecker("1.0.0", new HttpClient(new StubUpdateHandler("v1.0.0-windows")));
        var viewModel = BuildViewModel(dir, checker, clipboard: null, opened: null);

        await viewModel.CheckForUpdatesAsync();

        Assert.Equal(string.Empty, viewModel.UpdateText);
        Assert.False(viewModel.ApplyUpdateGuidance());
    }

    private sealed class StubUpdateHandler : HttpMessageHandler
    {
        private readonly string _tag;

        public StubUpdateHandler(string tag) => _tag = tag;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.Found)
            {
                Headers = { Location = new Uri($"https://github.com/rami2076/moost/releases/tag/{_tag}") },
            });
    }

    private static MainViewModel BuildViewModel(
        TempDir dir,
        UpdateChecker checker,
        List<string>? clipboard,
        List<string>? opened,
        string? processPath = null)
    {
        var sources = new SessionSources
        {
            ClaudeHistoryFile = dir.File("claude-history.jsonl"),
            ClaudeProjectsDirectory = Path.Combine(dir.Path, "p"),
            CodexHistoryFile = dir.File("c"),
            CodexSessionsDirectory = Path.Combine(dir.Path, "cs"),
            PiSessionsDirectory = Path.Combine(dir.Path, "ps"),
            HermesDatabase = dir.File("state.db"),
        };

        // プロセスパスは環境依存のため、winget 判定は UpdateGuidance 側で検証済み。
        // ここでは「手動導入ならリリースページ」の経路だけを見たいので、
        // 実プロセスパスが winget 管理下でない環境（開発実行）を前提にする。
        return new MainViewModel(
            sources,
            new MemoStore(dir.File("memos.json")),
            new ProjectStore(dir.File("projects.json")),
            new SettingsStore(dir.File("settings.json")),
            new TerminalLauncher(executableExists: _ => false, start: _ => true),
            copyToClipboard: clipboard is null ? null : clipboard.Add,
            updateChecker: checker,
            processPath: processPath,
            openUrl: opened is null ? null : opened.Add);
    }
}
