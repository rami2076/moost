namespace Moost.Core;

/// <summary>
/// 直近セッション一覧の読み取り元。UI からは <see cref="FromHome"/> で組み立てる。
/// </summary>
public sealed record SessionSources
{
    public required string ClaudeHistoryFile { get; init; }

    /// <summary>claude のセッション JSONL 群（会話抜粋・ai-title の読み取り元）。</summary>
    public required string ClaudeProjectsDirectory { get; init; }

    public required string CodexHistoryFile { get; init; }

    public required string CodexSessionsDirectory { get; init; }

    public required string PiSessionsDirectory { get; init; }

    public required string HermesDatabase { get; init; }

    /// <summary>実環境（<c>%USERPROFILE%</c>）の既定の置き場所から組み立てる。</summary>
    public static SessionSources FromHome(string? userProfile = null) => new()
    {
        ClaudeHistoryFile = SessionLocations.ClaudeHistoryFile(userProfile),
        ClaudeProjectsDirectory = SessionLocations.ClaudeProjectsDirectory(userProfile),
        CodexHistoryFile = SessionLocations.CodexHistoryFile(userProfile),
        CodexSessionsDirectory = SessionLocations.CodexSessionsDirectory(userProfile),
        PiSessionsDirectory = SessionLocations.PiSessionsDirectory(userProfile),
        HermesDatabase = SessionLocations.HermesStateDb(userProfile),
    };
}

/// <summary>
/// 複数エージェントの直近セッションを統合する（conformance E5）。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/SessionAggregator.swift</c>。
///
/// 1 つの読み取り元の失敗（CLI 未導入・履歴破損等）で一覧全体を空にしないよう、
/// 失敗した読み取り元は空扱いにする。
/// </summary>
public static class SessionAggregator
{
    /// <summary>
    /// claude / codex / pi / hermes の 4 系統を統合し、新しい順に <paramref name="limit"/> 件まで返す。
    /// </summary>
    public static IReadOnlyList<RecentSession> RecentSessions(SessionSources sources, int limit = 20)
    {
        var sessions = new List<RecentSession>();

        sessions.AddRange(Safe(Sources.Claude(sources, limit)));
        sessions.AddRange(Safe(Sources.Codex(sources, limit)));
        sessions.AddRange(Safe(Sources.Pi(sources, limit)));
        sessions.AddRange(Safe(Sources.Hermes(sources, limit)));

        return sessions
            .OrderByDescending(session => session.UpdatedAt)
            .Take(limit)
            .ToArray();
    }

    /// <summary>実環境のホームディレクトリから統合一覧を読む（UI 用の便利関数）。</summary>
    public static IReadOnlyList<RecentSession> RecentSessionsFromHome(string? userProfile = null, int limit = 20) =>
        RecentSessions(SessionSources.FromHome(userProfile), limit);

    private static IEnumerable<RecentSession> Safe(IEnumerable<RecentSession> read)
    {
        try
        {
            return read;
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
        catch (Microsoft.Data.Sqlite.SqliteException)
        {
            // Hermes の DB が壊れていても一覧全体を壊さない
            return [];
        }
    }

    /// <summary>各エージェントの読み取り。失敗した読み取り元は空配列になる。</summary>
    private static class Sources
    {
        public static IEnumerable<RecentSession> Claude(SessionSources sources, int limit)
        {
            try
            {
                return new SessionHistoryReader(
                    sources.ClaudeHistoryFile,
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
        /// （リファレンス実装 <c>codex_adapter.dart</c> と同じ足取り）。
        /// </summary>
        public static IEnumerable<RecentSession> Codex(SessionSources sources, int limit)
        {
            try
            {
                var entries = new CodexHistoryReader(sources.CodexHistoryFile, SummaryMarker.Value)
                    .AggregatedEntries();
                if (entries.Count == 0)
                {
                    return [];
                }

                var reader = new CodexRolloutReader(sources.CodexSessionsDirectory);
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

        public static IEnumerable<RecentSession> Pi(SessionSources sources, int limit)
        {
            try
            {
                return new PiSessionReader(sources.PiSessionsDirectory)
                    .RecentSessions(limit)
                    .Select(entry => new RecentSession
                    {
                        AgentId = ResumeCommand.PiAgentId,
                        SessionId = entry.SessionId,
                        ProjectPath = entry.ProjectPath,
                        LastPrompt = entry.LastPrompt,
                        UpdatedAt = entry.UpdatedAt,
                    });
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

        public static IEnumerable<RecentSession> Hermes(SessionSources sources, int limit)
        {
            try
            {
                return new HermesSessionReader(sources.HermesDatabase)
                    .RecentSessions(limit)
                    .Select(entry => new RecentSession
                    {
                        AgentId = ResumeCommand.HermesAgentId,
                        SessionId = entry.SessionId,
                        ProjectPath = entry.ProjectPath,
                        LastPrompt = entry.LastPrompt,
                        UpdatedAt = entry.UpdatedAt,
                        AiTitle = entry.AiTitle,
                    });
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
}
