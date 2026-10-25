using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 会話抜粋（transcript）の抽出。エージェント別のセッションファイル形式を検証する。
/// </summary>
public class TranscriptExtractorTests
{
    private static string WriteSession(TempDir dir, string directory, string name, IEnumerable<string> lines)
    {
        var target = Path.Combine(dir.Path, directory);
        Directory.CreateDirectory(target);
        var path = Path.Combine(target, name);
        File.WriteAllLines(path, lines);
        return path;
    }

    // MARK: claude

    [Fact]
    public void Claude_ExtractsRecentRallies()
    {
        using var dir = new TempDir();
        WriteSession(dir, "work-alpha", "S1.jsonl",
        [
            """{"type":"user","message":{"role":"user","content":[{"type":"text","text":"1st question"}]}}""",
            """{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"1st answer"}]}}""",
            """{"type":"user","message":{"role":"user","content":[{"type":"text","text":"2nd question"}]}}""",
            """{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"2nd answer"}]}}""",
        ]);

        var transcript = new ClaudeTranscriptExtractor(dir.Path).Extract("S1", rallies: 1);

        Assert.NotNull(transcript);
        Assert.Equal("User: 2nd question\nAssistant: 2nd answer", transcript);
    }

    [Fact]
    public void Claude_SkipsSidechainAndBrokenLines()
    {
        using var dir = new TempDir();
        WriteSession(dir, "p", "S1.jsonl",
        [
            """{"type":"user","isSidechain":true,"message":{"role":"user","content":[{"type":"text","text":"sidechain"}]}}""",
            "壊れた行",
            """{"type":"user","message":{"role":"user","content":[{"type":"text","text":"main question"}]}}""",
        ]);

        var transcript = new ClaudeTranscriptExtractor(dir.Path).Extract("S1");

        Assert.Equal("User: main question", transcript);
    }

    [Fact]
    public void Claude_SupportsStringContent()
    {
        using var dir = new TempDir();
        WriteSession(dir, "p", "S1.jsonl",
        [
            """{"type":"user","message":{"role":"user","content":"plain string"}}""",
        ]);

        Assert.Equal("User: plain string", new ClaudeTranscriptExtractor(dir.Path).Extract("S1"));
    }

    [Fact]
    public void Claude_MissingSession_ReturnsNull()
    {
        using var dir = new TempDir();
        Assert.Null(new ClaudeTranscriptExtractor(dir.Path).Extract("nope"));
    }

    // MARK: codex

    [Fact]
    public void Codex_ExtractsRallies_AndSkipsSystemUserPrefixes()
    {
        using var dir = new TempDir();
        var sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
        Directory.CreateDirectory(dir.Path);
        File.WriteAllLines(Path.Combine(dir.Path, $"rollout-2026-09-20T10-00-00-{sessionId}.jsonl"),
        [
            """{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>ctx"}]}}""",
            """{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"codex question"}]}}""",
            """{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"codex answer"}]}}""",
        ]);

        var transcript = new CodexTranscriptExtractor(new CodexRolloutReader(dir.Path)).Extract(sessionId);

        Assert.Equal("User: codex question\nAssistant: codex answer", transcript);
    }

    [Fact]
    public void Codex_MissingSession_ReturnsNull()
    {
        using var dir = new TempDir();
        Assert.Null(new CodexTranscriptExtractor(new CodexRolloutReader(dir.Path)).Extract("nope"));
    }

    // MARK: pi

    [Fact]
    public void Pi_RecentTakesLastRallies_FullTakesEverything()
    {
        using var dir = new TempDir();
        WriteSession(dir, "encoded", "20260920_P1.jsonl",
        [
            """{"type":"session","id":"P1","cwd":"/w","timestamp":"2026-09-20T09:00:00.000Z"}""",
            """{"type":"message","message":{"role":"user","content":[{"type":"text","text":"q1"}]}}""",
            """{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"a1"}]}}""",
            """{"type":"message","message":{"role":"user","content":[{"type":"text","text":"q2"}]}}""",
            """{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"a2"}]}}""",
        ]);

        var extractor = new PiTranscriptExtractor(dir.Path);

        Assert.Equal("User: q2\n\nAssistant: a2", extractor.Extract("P1", rallies: 1));
        Assert.Equal(
            "User: q1\n\nAssistant: a1\n\nUser: q2\n\nAssistant: a2",
            extractor.Extract("P1", full: true));
    }

    [Fact]
    public void Pi_FindsFileByHeaderId_WhenNameDoesNotContainIt()
    {
        using var dir = new TempDir();
        WriteSession(dir, "encoded", "unexpected-name.jsonl",
        [
            """{"type":"session","id":"P9","cwd":"/w","timestamp":"2026-09-20T09:00:00.000Z"}""",
            """{"type":"message","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}""",
        ]);

        Assert.Equal("User: hello", new PiTranscriptExtractor(dir.Path).Extract("P9"));
    }

    [Fact]
    public void Pi_MissingSession_ReturnsEmpty()
    {
        using var dir = new TempDir();
        Assert.Equal("", new PiTranscriptExtractor(dir.Path).Extract("nope"));
    }

    // MARK: hermes

    [Fact]
    public void Hermes_ExtractsUserAssistantAndToolLines()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "H1", "", "/w", 10);
        HermesDbFixture.AddMessage(db, "H1", "user", "hermes question", 1);
        HermesDbFixture.AddMessage(db, "H1", "assistant", "hermes answer", 2);
        HermesDbFixture.AddMessage(db, "H1", "tool", """{"output":"file.txt","exit_code":0}""", 3, toolName: "shell");

        var transcript = new HermesTranscriptExtractor(db).Extract("H1");

        Assert.Equal(
            "User: hermes question\nAssistant: hermes answer\nTool(shell): file.txt",
            transcript);
    }

    [Fact]
    public void Hermes_RecentKeepsLastRallies_AndIgnoresInactiveMessages()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "H1", "", "/w", 10);
        HermesDbFixture.AddMessage(db, "H1", "user", "old question", 1);
        HermesDbFixture.AddMessage(db, "H1", "user", "inactive question", 2, active: 0);
        HermesDbFixture.AddMessage(db, "H1", "user", "new question", 3);

        var extractor = new HermesTranscriptExtractor(db);

        Assert.Equal("User: new question", extractor.Extract("H1", rallies: 1));
        Assert.Equal("User: old question\n\nUser: new question", extractor.Extract("H1", full: true));
    }

    [Fact]
    public void Hermes_MissingDatabase_ReturnsEmpty()
    {
        using var dir = new TempDir();
        Assert.Equal("", new HermesTranscriptExtractor(dir.File("no.db")).Extract("H1"));
    }
}
