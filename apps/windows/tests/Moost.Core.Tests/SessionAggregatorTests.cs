using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance E5（複数エージェントの統合）と Codex の rollout 依存。
/// </summary>
public class SessionAggregatorTests
{
    private const string CodexSessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string CodexWithoutRollout = "11111111-2222-3333-4444-555555555555";

    private static (string ClaudeHistory, string CodexHistory, string CodexSessions) Prepare(TempDir dir)
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

        var rolloutDirectory = Path.Combine(dir.Path, "sessions", "2026", "09", "20");
        Directory.CreateDirectory(rolloutDirectory);
        File.WriteAllLines(
            Path.Combine(rolloutDirectory, $"rollout-2026-09-20T10-00-00-{CodexSessionId}.jsonl"),
            [
                """{"type":"session_meta","payload":{"cwd":"C:\\work\\x"}}""",
                """{"type":"user","message":"codex prompt"}""",
            ]);

        return (claudeHistory, codexHistory, Path.Combine(dir.Path, "sessions"));
    }

    [Fact]
    public void MergesAgents_NewestFirst()
    {
        using var dir = new TempDir();
        var (claudeHistory, codexHistory, codexSessions) = Prepare(dir);

        var sessions = SessionAggregator.RecentSessions(claudeHistory, codexHistory, codexSessions);

        // codex 2 秒 > claude 1 秒
        Assert.Equal([ResumeCommand.CodexAgentId, ResumeCommand.ClaudeAgentId],
            sessions.Select(session => session.AgentId));
    }

    [Fact]
    public void CodexWithoutRollout_IsExcluded()
    {
        using var dir = new TempDir();
        var (claudeHistory, codexHistory, codexSessions) = Prepare(dir);

        var sessions = SessionAggregator.RecentSessions(claudeHistory, codexHistory, codexSessions);

        Assert.DoesNotContain(sessions, session => session.SessionId == CodexWithoutRollout);
    }

    [Fact]
    public void CodexProjectPath_ComesFromRolloutSessionMeta()
    {
        using var dir = new TempDir();
        var (claudeHistory, codexHistory, codexSessions) = Prepare(dir);

        var sessions = SessionAggregator.RecentSessions(claudeHistory, codexHistory, codexSessions);
        var codex = Assert.Single(sessions, session => session.AgentId == ResumeCommand.CodexAgentId);

        Assert.Equal("C:\\work\\x", codex.ProjectPath);
        Assert.Equal("codex prompt", codex.LastPrompt);
    }

    [Fact]
    public void Limit_IsAppliedAfterMerging()
    {
        using var dir = new TempDir();
        var (claudeHistory, codexHistory, codexSessions) = Prepare(dir);

        var sessions = SessionAggregator.RecentSessions(claudeHistory, codexHistory, codexSessions, limit: 1);

        var session = Assert.Single(sessions);
        Assert.Equal(ResumeCommand.CodexAgentId, session.AgentId);
    }

    [Fact]
    public void MissingSources_YieldEmpty_WithoutThrowing()
    {
        using var dir = new TempDir();

        var sessions = SessionAggregator.RecentSessions(
            dir.File("no-claude.jsonl"),
            dir.File("no-codex.jsonl"),
            dir.File("no-sessions"));

        Assert.Empty(sessions);
    }
}
