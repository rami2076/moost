using System.Text;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance F1（表題フォールバック）と F2（ai-title の末尾走査）。
/// </summary>
public class RecentSessionTitleTests
{
    [Fact]
    public void F1_UsesAiTitle_WhenPresent()
    {
        var session = new RecentSession
        {
            AgentId = "claude-code",
            SessionId = "S",
            ProjectPath = "/w",
            LastPrompt = new string('p', 200),
            UpdatedAt = DateTime.UtcNow,
            AiTitle = "AI が付けた表題",
        };

        Assert.Equal("AI が付けた表題", session.DisplayTitle);
    }

    [Fact]
    public void F1_ShortPrompt_IsUsedAsIs()
    {
        Assert.Equal("short", RecentSession.FallbackTitle("short"));
        Assert.Equal(new string('a', 50), RecentSession.FallbackTitle(new string('a', 50)));
    }

    [Fact]
    public void F1_LongPrompt_IsCutTo50Runes()
    {
        var prompt = new string('a', 80);

        var title = RecentSession.FallbackTitle(prompt);

        Assert.Equal(new string('a', 50), title);
    }

    [Fact]
    public void F1_DoesNotSplitSurrogatePairs()
    {
        // 49 文字 + 絵文字（サロゲートペア = 2 UTF-16 単位）+ 後続
        var prompt = new string('a', 49) + "😀" + "bbbb";

        var title = RecentSession.FallbackTitle(prompt);

        Assert.Equal(new string('a', 49) + "😀", title);
        // runes で 50、UTF-16 では 51（ペアが分断されていない証拠）
        Assert.Equal(50, title.EnumerateRunes().Count());
        Assert.Equal(51, title.Length);
    }

    [Fact]
    public void F1_EmptyPrompt_IsEmpty()
    {
        Assert.Equal("", RecentSession.FallbackTitle(""));
    }

    [Fact]
    public void F1_DisplayTitle_FallsBackWhenAiTitleIsEmpty()
    {
        var session = new RecentSession
        {
            AgentId = "claude-code",
            SessionId = "S",
            ProjectPath = "/w",
            LastPrompt = "fallback prompt",
            UpdatedAt = DateTime.UtcNow,
            AiTitle = "",
        };

        Assert.Equal("fallback prompt", session.DisplayTitle);
    }

    [Fact]
    public void F2_ReadsNewestAiTitle_FromFixture()
    {
        var reader = new AiTitleReader(SpecPaths.TestData("claude_projects"));

        // 古い表題 → 新しい表題 の順に並ぶので、逆順走査で新しい方を採用する
        Assert.Equal(
            "新しい表題",
            reader.LatestAiTitle("0f0f0f0f-1111-2222-3333-444455556666"));
    }

    [Fact]
    public void F2_UnknownSession_ReturnsNull()
    {
        var reader = new AiTitleReader(SpecPaths.TestData("claude_projects"));
        Assert.Null(reader.LatestAiTitle("00000000-0000-0000-0000-000000000000"));
    }

    [Fact]
    public void F2_MissingProjectsDirectory_ReturnsNull()
    {
        using var dir = new TempDir();
        var reader = new AiTitleReader(dir.File("no-such-dir"));
        Assert.Null(reader.LatestAiTitle("S"));
    }

    [Fact]
    public void F2_FindsSessionFileByFileNameOnly()
    {
        using var dir = new TempDir();
        // ディレクトリ名は任意（エンコード規則に依存しない）
        var projectDir = Path.Combine(dir.Path, "any-encoded-project");
        Directory.CreateDirectory(projectDir);
        File.WriteAllLines(Path.Combine(projectDir, "sess-1.jsonl"),
        [
            """{"type":"user","message":"hi"}""",
            """{"type":"ai-title","aiTitle":"唯一の表題"}""",
        ]);

        Assert.Equal("唯一の表題", new AiTitleReader(dir.Path).LatestAiTitle("sess-1"));
    }

    [Fact]
    public void F2_OnlyLooksAtTheTail64KB()
    {
        using var dir = new TempDir();
        var projectDir = Path.Combine(dir.Path, "p");
        Directory.CreateDirectory(projectDir);

        var builder = new StringBuilder();
        builder.AppendLine("""{"type":"ai-title","aiTitle":"古すぎる表題"}""");
        // 64KB を超える埋め草を挟むと、先頭の ai-title は走査対象から外れる
        for (var index = 0; index < 2000; index++)
        {
            builder.AppendLine($$"""{"type":"user","message":"filler {{index}} ................................"}""");
        }

        builder.AppendLine("""{"type":"ai-title","aiTitle":"末尾の表題"}""");
        File.WriteAllText(Path.Combine(projectDir, "s.jsonl"), builder.ToString(), new UTF8Encoding(false));

        var reader = new AiTitleReader(dir.Path);
        Assert.Equal("末尾の表題", reader.LatestAiTitle("s"));
    }

    [Fact]
    public void F2_SkipsBrokenLineContainingAiTitle()
    {
        using var dir = new TempDir();
        var projectDir = Path.Combine(dir.Path, "p");
        Directory.CreateDirectory(projectDir);
        File.WriteAllLines(Path.Combine(projectDir, "s.jsonl"),
        [
            """{"type":"ai-title","aiTitle":"生きている表題"}""",
            """この行は "ai-title" を含むが JSON でない""",
        ]);

        Assert.Equal("生きている表題", new AiTitleReader(dir.Path).LatestAiTitle("s"));
    }

    [Fact]
    public void F2_TruncatedFirstLine_IsDiscarded()
    {
        using var dir = new TempDir();
        var projectDir = Path.Combine(dir.Path, "p");
        Directory.CreateDirectory(projectDir);
        // 先頭に長い行を置き、末尾チャンクの先頭で切れるようにする
        var longLine = $$"""{"type":"user","message":"{{new string('x', 200)}}"}""";
        var lines = new List<string>
        {
            longLine,
            """{"type":"ai-title","aiTitle":"採用される表題"}""",
        };
        File.WriteAllLines(Path.Combine(projectDir, "s.jsonl"), lines);

        var reader = new AiTitleReader(dir.Path, tailBytes: 60);
        Assert.Equal("採用される表題", reader.LatestAiTitle("s"));
    }
}
