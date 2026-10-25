namespace Moost.Core;

/// <summary>
/// 複数エージェントの直近セッションを統合する（conformance E5）。
/// リファレンス実装: <c>packages/core/lib/src/agent/adapter_registry.dart</c> の
/// <c>recentSessions</c>（全 adapter をマージし新しい順に並べ limit で切る）。
///
/// 1 つの読み取り元の失敗（CLI 未導入・履歴破損等）で一覧全体を空にしないよう、
/// 失敗した読み取り元は空扱いにする。
///
/// 現時点（#99）は claude と codex を統合する。pi / hermes は #101 で追加する。
/// </summary>
public static class SessionAggregator
{
    /// <summary>
    /// claude と codex の履歴を統合し、新しい順に <paramref name="limit"/> 件まで返す。
    /// </summary>
    public static IReadOnlyList<RecentSession> RecentSessions(
        string claudeHistoryFile,
        string codexHistoryFile,
        string codexSessionsDirectory,
        int limit = 20)
    {
        var claude = SafeClaude(claudeHistoryFile, limit);
        var codex = SafeCodex(codexHistoryFile, codexSessionsDirectory, limit);

        return claude
            .Concat(codex)
            .OrderByDescending(session => session.UpdatedAt)
            .Take(limit)
            .ToArray();
    }

    /// <summary>実環境のホームディレクトリから統合一覧を読む（UI 用の便利関数）。</summary>
    public static IReadOnlyList<RecentSession> RecentSessionsFromHome(
        string? userProfile = null,
        int limit = 20) =>
        RecentSessions(
            SessionLocations.ClaudeHistoryFile(userProfile),
            SessionLocations.CodexHistoryFile(userProfile),
            SessionLocations.CodexSessionsDirectory(userProfile),
            limit);

    private static IReadOnlyList<RecentSession> SafeClaude(string historyFile, int limit)
    {
        try
        {
            return new SessionHistoryReader(
                historyFile,
                ResumeCommand.ClaudeAgentId,
                SummaryMarker.Value).RecentSessions(limit);
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }

    /// <summary>
    /// codex は rollout が消えたセッションを一覧から除外し、rollout から cwd を読む
    /// （リファレンス実装 <c>codex_adapter.dart</c> の recentSessions と同じ足取り）。
    /// </summary>
    private static IReadOnlyList<RecentSession> SafeCodex(
        string historyFile,
        string sessionsDirectory,
        int limit)
    {
        try
        {
            var entries = new CodexHistoryReader(historyFile, SummaryMarker.Value).AggregatedEntries();
            if (entries.Count == 0)
            {
                return [];
            }

            var reader = new CodexRolloutReader(sessionsDirectory);
            var rollouts = reader.Scan();

            var sessions = new List<RecentSession>(Math.Min(entries.Count, limit));
            foreach (var entry in entries)
            {
                if (!rollouts.TryGetValue(entry.SessionId, out var rolloutFile))
                {
                    // rollout が無いセッションは `codex resume` でも復帰できないので除外する
                    continue;
                }

                sessions.Add(new RecentSession
                {
                    AgentId = ResumeCommand.CodexAgentId,
                    SessionId = entry.SessionId,
                    ProjectPath = reader.ReadCwd(rolloutFile) ?? string.Empty,
                    LastPrompt = entry.LastPrompt,
                    UpdatedAt = entry.UpdatedAt,
                });

                if (sessions.Count >= limit)
                {
                    break;
                }
            }

            return sessions;
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }
}
