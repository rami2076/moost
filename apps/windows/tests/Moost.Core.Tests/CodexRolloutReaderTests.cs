using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// Codex rollout の探索と <c>session_meta.cwd</c> の読み取り（E6 の前提）。
/// </summary>
public class CodexRolloutReaderTests
{
    private const string SessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

    [Fact]
    public void Scan_FindsRolloutInNestedDateDirectories()
    {
        using var dir = new TempDir();
        var nested = Path.Combine(dir.Path, "2026", "09", "20");
        Directory.CreateDirectory(nested);
        var rollout = Path.Combine(nested, $"rollout-2026-09-20T10-00-00-{SessionId}.jsonl");
        File.WriteAllText(rollout, """{"type":"session_meta","payload":{"cwd":"/w"}}""" + "\n");

        var index = new CodexRolloutReader(dir.Path).Scan();

        Assert.Equal(rollout, index[SessionId]);
    }

    [Fact]
    public void Scan_PrefersLexicographicallyLatestFile_ForDuplicateSessionId()
    {
        using var dir = new TempDir();
        Directory.CreateDirectory(dir.Path);
        var older = Path.Combine(dir.Path, $"rollout-2026-09-20T10-00-00-{SessionId}.jsonl");
        var newer = Path.Combine(dir.Path, $"rollout-2026-09-21T10-00-00-{SessionId}.jsonl");
        File.WriteAllText(older, "{}\n");
        File.WriteAllText(newer, "{}\n");

        var index = new CodexRolloutReader(dir.Path).Scan();

        Assert.Equal(newer, index[SessionId]);
    }

    [Fact]
    public void Scan_IgnoresFilesWithoutSessionIdSuffix()
    {
        using var dir = new TempDir();
        File.WriteAllText(Path.Combine(dir.Path, "rollout-2026-09-20T10-00-00-not-a-uuid.jsonl"), "{}\n");
        File.WriteAllText(Path.Combine(dir.Path, "other.jsonl"), "{}\n");

        Assert.Empty(new CodexRolloutReader(dir.Path).Scan());
    }

    [Fact]
    public void ReadCwd_ReturnsPayloadCwd()
    {
        using var dir = new TempDir();
        var rollout = dir.File("rollout.jsonl");
        File.WriteAllLines(rollout,
        [
            """{"type":"user","message":"before meta"}""",
            """{"type":"session_meta","payload":{"cwd":"C:\\work\\alpha","id":"x"}}""",
        ]);

        Assert.Equal("C:\\work\\alpha", new CodexRolloutReader(dir.Path).ReadCwd(rollout));
    }

    [Fact]
    public void ReadCwd_ReturnsNull_WhenMetaIsMissing()
    {
        using var dir = new TempDir();
        var rollout = dir.File("rollout.jsonl");
        File.WriteAllLines(rollout, ["""{"type":"user","message":"no meta"}"""]);

        Assert.Null(new CodexRolloutReader(dir.Path).ReadCwd(rollout));
    }

    [Fact]
    public void ReadCwd_ReturnsNull_WhenFileIsMissing()
    {
        using var dir = new TempDir();
        Assert.Null(new CodexRolloutReader(dir.Path).ReadCwd(dir.File("absent.jsonl")));
    }

    [Fact]
    public void Scan_OnMissingDirectory_ReturnsEmpty()
    {
        using var dir = new TempDir();
        Assert.Empty(new CodexRolloutReader(dir.File("no-such-dir")).Scan());
    }
}
