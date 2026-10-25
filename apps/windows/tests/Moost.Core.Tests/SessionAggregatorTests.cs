using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance E5（複数エージェントの統合）。claude / codex / pi / hermes の 4 系統を扱う。
/// </summary>
public class SessionAggregatorTests
{
    private const string CodexSessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string CodexWithoutRollout = "11111111-2222-3333-4444-555555555555";

    private static SessionSources Prepare(TempDir dir)
    {
        var claudeHistory = dir.File("claude-history.jsonl");
        File.WriteAllLines(claudeHistory,
        [
            """{"display":"claude prompt","timestamp":1000,"project":"/work/c","sessionId":"S-CLAUDE"}""",
        ]);

        var codexHistory = dir.File("codex-history.jsonl");
        File.WriteAllLines(codexHistory,
        [
            $$"""{"session_id":"{{CodexSessionId}}","ts":2,"text":"codex prompt"}""",
            $$"""{"session_id":"{{CodexWithoutRollout}}","ts":3,"text":"rollout が無いセッション"}""",
        ]);

        var rolloutDirectory = Path.Combine(dir.Path, "codex-sessions", "2026", "09", "20");
        Directory.CreateDirectory(rolloutDirectory);
        File.WriteAllLines(
            Path.Combine(rolloutDirectory, $"rollout-2026-09-20T10-00-00-{CodexSessionId}.jsonl"),
            [
                """{"type":"session_meta","payload":{"cwd":"C:\\work\\x"}}""",
                """{"type":"user","message":"codex prompt"}""",
            ]);

        // pi: 4 秒（codex の 2 秒より新しい）
        var piDirectory = Path.Combine(dir.Path, "pi-sessions", "cwd");
        Directory.CreateDirectory(piDirectory);
        File.WriteAllLines(Path.Combine(piDirectory, "p.jsonl"),
        [
            """{"type":"session","id":"P-1","cwd":"/work/pi","timestamp":"1970-01-01T00:00:04.000Z"}""",
            """{"type":"message","timestamp":"1970-01-01T00:00:04.000Z","message":{"role":"user","content":[{"type":"text","text":"pi prompt"}]}}""",
        ]);

        // hermes: 5 秒（最新）
        var hermesDb = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(hermesDb, "H-1", "", "/work/hermes", 5);
        HermesDbFixture.AddMessage(hermesDb, "H-1", "user", "hermes prompt", 5);

        return new SessionSources
        {
            ClaudeHistoryFile = claudeHistory,
            CodexHistoryFile = codexHistory,
            CodexSessionsDirectory = Path.Combine(dir.Path, "codex-sessions"),
            PiSessionsDirectory = Path.Combine(dir.Path, "pi-sessions"),
            HermesDatabase = hermesDb,
        };
    }

    [Fact]
    public void MergesAllFourAgents_NewestFirst()
    {
        using var dir = new TempDir();
        var sources = Prepare(dir);

        var sessions = SessionAggregator.RecentSessions(sources);

        // hermes 5 秒 > pi 4 秒 > codex 2 秒 > claude 1 秒
        Assert.Equal(
            [
                ResumeCommand.HermesAgentId,
                ResumeCommand.PiAgentId,
                ResumeCommand.CodexAgentId,
                ResumeCommand.ClaudeAgentId,
            ],
            sessions.Select(session => session.AgentId));
    }

    [Fact]
    public void CodexWithoutRollout_IsExcluded()
    {
        using var dir = new TempDir();
        var sessions = SessionAggregator.RecentSessions(Prepare(dir));

        Assert.DoesNotContain(sessions, session => session.SessionId == CodexWithoutRollout);
    }

    [Fact]
    public void CodexProjectPath_ComesFromRolloutSessionMeta()
    {
        using var dir = new TempDir();
        var sessions = SessionAggregator.RecentSessions(Prepare(dir));
        var codex = Assert.Single(sessions, session => session.AgentId == ResumeCommand.CodexAgentId);

        Assert.Equal("C:\\work\\x", codex.ProjectPath);
        Assert.Equal("codex prompt", codex.LastPrompt);
    }

    [Fact]
    public void HermesCarriesAiTitle()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "H-2", "自動タイトル", "/w", 10);
        HermesDbFixture.AddMessage(db, "H-2", "user", "本文プロンプト", 10);

        var sessions = SessionAggregator.RecentSessions(new SessionSources
        {
            ClaudeHistoryFile = dir.File("none-1"),
            CodexHistoryFile = dir.File("none-2"),
            CodexSessionsDirectory = dir.File("none-3"),
            PiSessionsDirectory = dir.File("none-4"),
            HermesDatabase = db,
        });

        var hermes = Assert.Single(sessions);
        Assert.Equal("自動タイトル", hermes.DisplayTitle);
        Assert.Equal("本文プロンプト", hermes.LastPrompt);
    }

    [Fact]
    public void Limit_IsAppliedAfterMerging()
    {
        using var dir = new TempDir();
        var sessions = SessionAggregator.RecentSessions(Prepare(dir), limit: 2);

        Assert.Equal(
            [ResumeCommand.HermesAgentId, ResumeCommand.PiAgentId],
            sessions.Select(session => session.AgentId));
    }

    [Fact]
    public void MissingSources_YieldEmpty_WithoutThrowing()
    {
        using var dir = new TempDir();

        var sessions = SessionAggregator.RecentSessions(new SessionSources
        {
            ClaudeHistoryFile = dir.File("no-claude.jsonl"),
            CodexHistoryFile = dir.File("no-codex.jsonl"),
            CodexSessionsDirectory = dir.File("no-sessions"),
            PiSessionsDirectory = dir.File("no-pi"),
            HermesDatabase = dir.File("no-state.db"),
        });

        Assert.Empty(sessions);
    }

    [Fact]
    public void FromHome_BuildsExpectedPaths()
    {
        var profile = Path.Combine("C:", "Users", "someone");
        var sources = SessionSources.FromHome(profile);

        Assert.Equal(SessionLocations.ClaudeHistoryFile(profile), sources.ClaudeHistoryFile);
        Assert.Equal(SessionLocations.CodexSessionsDirectory(profile), sources.CodexSessionsDirectory);
        Assert.Equal(SessionLocations.PiSessionsDirectory(profile), sources.PiSessionsDirectory);
        Assert.Equal(SessionLocations.HermesStateDb(profile), sources.HermesDatabase);
    }
}
