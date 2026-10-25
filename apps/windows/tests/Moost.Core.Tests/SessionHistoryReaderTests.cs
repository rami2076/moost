using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance E1〜E5（<c>history.jsonl</c> の集約）。Fixture は spec/testdata をそのまま使う。
/// </summary>
public class SessionHistoryReaderTests
{
    private static SessionHistoryReader FixtureReader() => new(
        SpecPaths.TestData("history.jsonl"),
        ResumeCommand.ClaudeAgentId,
        SummaryMarker.ConformanceMarker);

    [Fact]
    public void E2_AggregatesBySessionId_UsingLatestTimestamp()
    {
        var sessions = FixtureReader().RecentSessions();

        var s1 = Assert.Single(sessions, session => session.SessionId == "S1");
        Assert.Equal("second prompt", s1.LastPrompt);
        Assert.Equal(new DateTime(1970, 1, 1, 0, 0, 2, DateTimeKind.Utc), s1.UpdatedAt);

        var s3 = Assert.Single(sessions, session => session.SessionId == "S3");
        Assert.Equal("third prompt", s3.LastPrompt);
    }

    [Fact]
    public void E1_SkipsBrokenAndEmptyLines_WithoutCrashing()
    {
        // Fixture には「JSON でない行」と空行が含まれる。それでも 3 セッションが読める
        var sessions = FixtureReader().RecentSessions();
        Assert.Equal(3, sessions.Count);
    }

    [Fact]
    public void E3_ExcludesForkLinesOnly_KeepingMixedSessions()
    {
        var sessions = FixtureReader().RecentSessions();

        // マーカー行のみの S4 は消える
        Assert.DoesNotContain(sessions, session => session.SessionId == "S4");

        // 混在する S2 は通常プロンプト側の最新が残る（行単位の除外）
        var s2 = Assert.Single(sessions, session => session.SessionId == "S2");
        Assert.Equal("normal prompt", s2.LastPrompt);
        Assert.Equal("/work/beta", s2.ProjectPath);
    }

    [Fact]
    public void E4_TimestampsAreUtcMilliseconds()
    {
        var sessions = FixtureReader().RecentSessions();

        // 新しい順: S3(4000ms) > S1(2000ms) > S2(1500ms)
        Assert.Equal(["S3", "S1", "S2"], sessions.Select(session => session.SessionId));
        Assert.All(sessions, session => Assert.Equal(DateTimeKind.Utc, session.UpdatedAt.Kind));
        Assert.Equal(new DateTime(1970, 1, 1, 0, 0, 4, DateTimeKind.Utc), sessions[0].UpdatedAt);
    }

    [Fact]
    public void E5_LimitCapsTheNewestEntries()
    {
        var sessions = FixtureReader().RecentSessions(limit: 2);

        Assert.Equal(2, sessions.Count);
        Assert.Equal(["S3", "S1"], sessions.Select(session => session.SessionId));
    }

    [Fact]
    public void AgentIdIsStampedOnEverySession()
    {
        Assert.All(
            FixtureReader().RecentSessions(),
            session => Assert.Equal(ResumeCommand.ClaudeAgentId, session.AgentId));
    }

    [Fact]
    public void MissingFile_YieldsEmptyList()
    {
        using var dir = new TempDir();
        var reader = new SessionHistoryReader(dir.File("history.jsonl"), "claude-code", SummaryMarker.Value);

        Assert.Empty(reader.RecentSessions());
    }

    [Fact]
    public void ProductionMarker_ExcludesRealSummaryPrompts()
    {
        using var dir = new TempDir();
        var path = dir.File("history.jsonl");
        File.WriteAllLines(path,
        [
            """{"display":"real prompt","timestamp":1000,"project":"/w","sessionId":"A"}""",
            $$"""{"display":"{{SummaryMarker.Value}} 要約してください","timestamp":2000,"project":"/w","sessionId":"A"}""",
            $$"""{"display":"{{SummaryMarker.Value}} 抜粋です","timestamp":3000,"project":"/w","sessionId":"B"}""",
        ]);

        var sessions = new SessionHistoryReader(path, "claude-code", SummaryMarker.Value).RecentSessions();

        var session = Assert.Single(sessions);
        Assert.Equal("A", session.SessionId);
        Assert.Equal("real prompt", session.LastPrompt);
    }
}
