using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// <c>history.jsonl</c>（Claude Code 系）を集約して直近セッション一覧の元データを作る
/// （conformance E1〜E5）。リファレンス実装:
/// <c>packages/core/lib/src/agent/claude_code/session_history_reader.dart</c>。
///
/// 1 行 = 1 プロンプトの JSONL（<c>display</c> / <c>timestamp</c>[epoch ms] / <c>project</c> / <c>sessionId</c>）。
/// 内部フォーマット変更でクラッシュしないよう、パースできない行はすべてスキップする。
/// </summary>
public sealed class SessionHistoryReader
{
    private readonly string _historyFile;
    private readonly string _agentId;
    private readonly string _excludeMarker;

    public SessionHistoryReader(string historyFile, string agentId, string excludeMarker)
    {
        _historyFile = historyFile;
        _agentId = agentId;
        _excludeMarker = excludeMarker;
    }

    /// <summary>
    /// sessionId 単位に最新 timestamp の行を採用し、新しい順に <paramref name="limit"/> 件まで返す。
    /// </summary>
    public IReadOnlyList<RecentSession> RecentSessions(int limit = 20)
    {
        // sessionId → 最新行
        var latestBySession = new Dictionary<string, (string Display, string Project, long Timestamp)>(StringComparer.Ordinal);

        foreach (var line in JsonlLine.ReadLines(_historyFile))
        {
            if (!JsonlLine.TryParseObject(line, out var json)
                || !JsonRead.TryString(json, "display", out var display)
                || !TryGetLong(json, "timestamp", out var timestamp)
                || !JsonRead.TryString(json, "project", out var project)
                || !JsonRead.TryString(json, "sessionId", out var sessionId))
            {
                continue;
            }

            // 要約用フォークは行単位で除外する（E3）。
            // セッション単位で落とすと、通常プロンプトが混在するセッションまで消えてしまう。
            if (display.StartsWith(_excludeMarker, StringComparison.Ordinal))
            {
                continue;
            }

            if (latestBySession.TryGetValue(sessionId, out var existing) && existing.Timestamp >= timestamp)
            {
                continue;
            }

            latestBySession[sessionId] = (display, project, timestamp);
        }

        return latestBySession
            .Select(pair => new RecentSession
            {
                AgentId = _agentId,
                SessionId = pair.Key,
                ProjectPath = pair.Value.Project,
                LastPrompt = pair.Value.Display,
                // epoch ミリ秒 → UTC（E4）
                UpdatedAt = DateTimeOffset.FromUnixTimeMilliseconds(pair.Value.Timestamp).UtcDateTime,
            })
            .OrderByDescending(session => session.UpdatedAt)
            .Take(limit)
            .ToArray();
    }

    private static bool TryGetLong(JsonObject json, string key, out long value)
    {
        value = 0;
        if (json[key] is JsonValue node
            && node.GetValueKind() == System.Text.Json.JsonValueKind.Number
            && node.TryGetValue<long>(out var number))
        {
            value = number;
            return true;
        }

        return false;
    }
}
