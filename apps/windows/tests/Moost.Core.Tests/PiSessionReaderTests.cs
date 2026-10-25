using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// pi のセッション JSONL 読み取り（#101）。
/// </summary>
public class PiSessionReaderTests
{
    private const string Header =
        """{"type":"session","id":"P1","cwd":"C:\\work\\pi","timestamp":"2026-09-20T09:00:00.000Z"}""";

    private static string WriteSession(TempDir dir, string name, IEnumerable<string> lines)
    {
        var directory = Path.Combine(dir.Path, "encoded-cwd");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, name);
        File.WriteAllLines(path, lines);
        return path;
    }

    [Fact]
    public void ReadsHeaderAndLastUserPrompt()
    {
        using var dir = new TempDir();
        WriteSession(dir, "20260920_P1.jsonl",
        [
            Header,
            """{"type":"message","timestamp":"2026-09-20T09:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"first question"}]}}""",
            """{"type":"message","timestamp":"2026-09-20T09:02:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"answer"}]}}""",
            """{"type":"message","timestamp":"2026-09-20T09:03:00.000Z","message":{"role":"user","content":[{"type":"text","text":"second question"}]}}""",
        ]);

        var entry = Assert.Single(new PiSessionReader(dir.Path).RecentSessions());

        Assert.Equal("P1", entry.SessionId);
        Assert.Equal("C:\\work\\pi", entry.ProjectPath);
        Assert.Equal("second question", entry.LastPrompt);
        Assert.Equal(new DateTime(2026, 9, 20, 9, 3, 0, DateTimeKind.Utc), entry.UpdatedAt);
    }

    [Fact]
    public void JoinsMultipleTextParts_WithSpace()
    {
        using var dir = new TempDir();
        WriteSession(dir, "s.jsonl",
        [
            Header,
            """{"type":"message","timestamp":"2026-09-20T09:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"part1"},{"type":"text","text":"part2"},{"type":"image","url":"x"}]}}""",
        ]);

        var entry = Assert.Single(new PiSessionReader(dir.Path).RecentSessions());
        Assert.Equal("part1 part2", entry.LastPrompt);
    }

    [Fact]
    public void SkipsBrokenLines_AndFilesWithoutHeader()
    {
        using var dir = new TempDir();
        WriteSession(dir, "good.jsonl",
        [
            Header,
            "この行は JSON でない",
            "",
            """{"type":"message","timestamp":"2026-09-20T09:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"q"}]}}""",
        ]);
        WriteSession(dir, "no-header.jsonl",
        [
            """{"type":"message","message":{"role":"user","content":[]}}""",
        ]);

        var entry = Assert.Single(new PiSessionReader(dir.Path).RecentSessions());
        Assert.Equal("P1", entry.SessionId);
        Assert.Equal("q", entry.LastPrompt);
    }

    [Fact]
    public void OrdersNewestFirst_AndAppliesLimit()
    {
        using var dir = new TempDir();
        WriteSession(dir, "old.jsonl",
        [
            """{"type":"session","id":"OLD","cwd":"/old","timestamp":"2026-09-01T00:00:00.000Z"}""",
            """{"type":"message","timestamp":"2026-09-01T00:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"old"}]}}""",
        ]);
        WriteSession(dir, "new.jsonl",
        [
            """{"type":"session","id":"NEW","cwd":"/new","timestamp":"2026-09-02T00:00:00.000Z"}""",
            """{"type":"message","timestamp":"2026-09-02T00:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"new"}]}}""",
        ]);

        var sessions = new PiSessionReader(dir.Path).RecentSessions();
        Assert.Equal(["NEW", "OLD"], sessions.Select(entry => entry.SessionId));

        var limited = new PiSessionReader(dir.Path).RecentSessions(limit: 1);
        Assert.Equal("NEW", Assert.Single(limited).SessionId);
    }

    [Fact]
    public void MissingDirectory_YieldsEmpty()
    {
        using var dir = new TempDir();
        Assert.Empty(new PiSessionReader(dir.File("no-such-dir")).RecentSessions());
    }

    [Fact]
    public void HeaderWithoutCwd_UsesEmptyProjectPath()
    {
        using var dir = new TempDir();
        WriteSession(dir, "s.jsonl",
        [
            """{"type":"session","id":"P2","timestamp":"2026-09-20T09:00:00.000Z"}""",
        ]);

        var entry = Assert.Single(new PiSessionReader(dir.Path).RecentSessions());
        Assert.Equal("", entry.ProjectPath);
        // ユーザー発言が無ければ最終プロンプトは空（表題フォールバックは UI 側）
        Assert.Equal("", entry.LastPrompt);
    }
}
