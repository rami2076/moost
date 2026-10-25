using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 要約ファサード（エージェント別の分岐とローカル抽出）とメモリキャッシュ。
/// </summary>
public class SessionSummarizerTests
{
    private static SessionSources Sources(TempDir dir) => new()
    {
        ClaudeHistoryFile = dir.File("claude-history.jsonl"),
        ClaudeProjectsDirectory = Path.Combine(dir.Path, "claude-projects"),
        CodexHistoryFile = dir.File("codex-history.jsonl"),
        CodexSessionsDirectory = Path.Combine(dir.Path, "codex-sessions"),
        PiSessionsDirectory = Path.Combine(dir.Path, "pi-sessions"),
        HermesDatabase = dir.File("state.db"),
    };

    [Fact]
    public void IsLocalOnly_IsTrueForPiAndHermes()
    {
        Assert.True(SessionSummarizer.IsLocalOnly(ResumeCommand.PiAgentId));
        Assert.True(SessionSummarizer.IsLocalOnly(ResumeCommand.HermesAgentId));
        Assert.False(SessionSummarizer.IsLocalOnly(ResumeCommand.ClaudeAgentId));
        Assert.False(SessionSummarizer.IsLocalOnly(ResumeCommand.CodexAgentId));
    }

    [Fact]
    public async Task Pi_ReturnsLocalExtraction_WithoutCallingAnyCli()
    {
        using var dir = new TempDir();
        var sources = Sources(dir);
        Directory.CreateDirectory(sources.PiSessionsDirectory);
        File.WriteAllLines(Path.Combine(sources.PiSessionsDirectory, "20260920_P1.jsonl"),
        [
            """{"type":"session","id":"P1","cwd":"/w","timestamp":"2026-09-20T09:00:00.000Z"}""",
            """{"type":"message","message":{"role":"user","content":[{"type":"text","text":"pi question"}]}}""",
        ]);

        var summarizer = new SessionSummarizer(sources, _ => throw new InvalidOperationException("CLI は呼ばれないはず"));

        var summary = await summarizer.SummarizeAsync(
            ResumeCommand.PiAgentId, "P1", SummaryScope.Recent);

        Assert.Equal("User: pi question", summary);
    }

    [Fact]
    public async Task Hermes_ReturnsLocalExtraction()
    {
        using var dir = new TempDir();
        var sources = Sources(dir);
        var db = HermesDbFixture.Create(sources.HermesDatabase);
        HermesDbFixture.AddSession(db, "H1", "", "/w", 10);
        HermesDbFixture.AddMessage(db, "H1", "user", "hermes question", 1);

        var summarizer = new SessionSummarizer(sources, _ => null);

        var summary = await summarizer.SummarizeAsync(
            ResumeCommand.HermesAgentId, "H1", SummaryScope.Full);

        Assert.Equal("User: hermes question", summary);
    }

    [Fact]
    public async Task Claude_WithoutCli_ThrowsWithGuidance()
    {
        using var dir = new TempDir();
        var summarizer = new SessionSummarizer(Sources(dir), _ => null);

        var exception = await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeAsync(ResumeCommand.ClaudeAgentId, "S", SummaryScope.Recent));

        Assert.Contains("見つかりません", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Claude_WithoutSessionFile_ThrowsAboutExpiry()
    {
        using var dir = new TempDir();
        var claude = FakeCli.ClaudeEcho(dir);
        var summarizer = new SessionSummarizer(Sources(dir), _ => claude);

        var exception = await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeAsync(ResumeCommand.ClaudeAgentId, "missing", SummaryScope.Recent));

        Assert.Contains("読み取れませんでした", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Claude_Recent_SummarizesTranscriptFromSessionFile()
    {
        using var dir = new TempDir();
        var sources = Sources(dir);
        var projectDirectory = Path.Combine(sources.ClaudeProjectsDirectory, "work-alpha");
        Directory.CreateDirectory(projectDirectory);
        File.WriteAllLines(Path.Combine(projectDirectory, "S1.jsonl"),
        [
            """{"type":"user","message":{"role":"user","content":[{"type":"text","text":"claude question"}]}}""",
            """{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"claude answer"}]}}""",
        ]);

        var claude = FakeCli.ClaudeEcho(dir);
        var summarizer = new SessionSummarizer(sources, _ => claude, TimeSpan.FromSeconds(60));

        var summary = await summarizer.SummarizeAsync(
            ResumeCommand.ClaudeAgentId, "S1", SummaryScope.Recent, rallies: 1, workingDirectory: dir.Path);

        Assert.Contains("ENV=", summary, StringComparison.Ordinal);
        var args = File.ReadAllText(Path.Combine(dir.Path, "args.txt"));
        Assert.StartsWith("-p|--model|haiku|", args, StringComparison.Ordinal);
        Assert.Contains(ClaudeSummarizer.Marker, args, StringComparison.Ordinal);
        Assert.Equal(
            "User: claude question\nAssistant: claude answer",
            File.ReadAllText(Path.Combine(dir.Path, "stdin.txt")));
    }

    [Fact]
    public async Task Codex_Recent_SummarizesRolloutTranscript()
    {
        using var dir = new TempDir();
        var sources = Sources(dir);
        var sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
        Directory.CreateDirectory(sources.CodexSessionsDirectory);
        File.WriteAllLines(Path.Combine(sources.CodexSessionsDirectory, $"rollout-2026-09-20T10-00-00-{sessionId}.jsonl"),
        [
            """{"type":"session_meta","payload":{"cwd":"C:\\w"}}""",
            """{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"codex question"}]}}""",
        ]);

        var codex = FakeCli.CodexEchoArgs(dir);
        var summarizer = new SessionSummarizer(sources, _ => codex, TimeSpan.FromSeconds(60));

        var summary = await summarizer.SummarizeAsync(
            ResumeCommand.CodexAgentId, sessionId, SummaryScope.Recent);

        Assert.StartsWith("ARGS=exec|--ephemeral|", summary, StringComparison.Ordinal);
    }

    [Fact]
    public async Task UnknownAgent_Throws()
    {
        using var dir = new TempDir();
        var summarizer = new SessionSummarizer(Sources(dir));

        var exception = await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeAsync("gemini", "S", SummaryScope.Recent));

        Assert.Contains("不明なエージェント", exception.Message, StringComparison.Ordinal);
    }
}

/// <summary>
/// 要約のメモリキャッシュ（ADR-002・永続化しない）。
/// </summary>
public class SummaryCacheTests
{
    [Fact]
    public void SeparatesEntriesByScopeAndRallyCount()
    {
        var cache = new SummaryCache();
        cache.Put("S1", SummaryScope.Recent, 1, "recent1");
        cache.Put("S1", SummaryScope.Recent, 3, "recent3");
        cache.Put("S1", SummaryScope.Full, 1, "full");

        Assert.Equal("recent1", cache.Get("S1", SummaryScope.Recent, 1));
        Assert.Equal("recent3", cache.Get("S1", SummaryScope.Recent, 3));
        Assert.Equal("full", cache.Get("S1", SummaryScope.Full, 1));
        Assert.Null(cache.Get("S2", SummaryScope.Recent, 1));
    }

    [Fact]
    public void Clear_RemovesEverything()
    {
        var cache = new SummaryCache();
        cache.Put("S1", SummaryScope.Full, 1, "x");
        Assert.Equal(1, cache.Count);

        cache.Clear();

        Assert.Equal(0, cache.Count);
        Assert.Null(cache.Get("S1", SummaryScope.Full, 1));
    }
}
