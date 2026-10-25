using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// <c>history.jsonl</c>（Codex）を集約した 1 セッション分の元データ（conformance E6・E7）。
///
/// Claude Code と違い history 行はプロジェクトパスを持たないため、
/// <see cref="RecentSession"/> を作るにはセッション本体（rollout JSONL）の
/// <c>session_meta.cwd</c> を別途引く必要がある（<see cref="CodexRolloutReader"/>）。
/// </summary>
public sealed record CodexHistoryEntry
{
    public required string SessionId { get; init; }

    public required string LastPrompt { get; init; }

    public required DateTime UpdatedAt { get; init; }
}

/// <summary>
/// <c>%USERPROFILE%\.codex\history.jsonl</c> を集約する（conformance E6・E7）。
/// リファレンス実装: <c>packages/core/lib/src/agent/codex/codex_history_reader.dart</c>。
///
/// 1 行 = 1 プロンプトの JSONL（<c>session_id</c> / <c>ts</c>[epoch 秒] / <c>text</c>）。
/// </summary>
public sealed class CodexHistoryReader
{
    private readonly string _historyFile;
    private readonly string _excludeMarker;

    public CodexHistoryReader(string historyFile, string excludeMarker)
    {
        _historyFile = historyFile;
        _excludeMarker = excludeMarker;
    }

    /// <summary>
    /// 全セッションを最新順で返す。呼び出し側が rollout の有無で間引くため、
    /// ここでは件数を切らない。
    /// </summary>
    public IReadOnlyList<CodexHistoryEntry> AggregatedEntries()
    {
        var latestBySession = new Dictionary<string, (string Text, long Ts)>(StringComparer.Ordinal);

        foreach (var line in JsonlLine.ReadLines(_historyFile))
        {
            if (!JsonlLine.TryParseObject(line, out var json)
                || !JsonRead.TryString(json, "session_id", out var sessionId)
                || !TryGetLong(json, "ts", out var ts)
                || !JsonRead.TryString(json, "text", out var text))
            {
                continue;
            }

            // 要約用フォークは行単位で除外（E7）
            if (text.StartsWith(_excludeMarker, StringComparison.Ordinal))
            {
                continue;
            }

            if (latestBySession.TryGetValue(sessionId, out var existing) && existing.Ts >= ts)
            {
                continue;
            }

            latestBySession[sessionId] = (text, ts);
        }

        return latestBySession
            .Select(pair => new CodexHistoryEntry
            {
                SessionId = pair.Key,
                LastPrompt = pair.Value.Text,
                // ts は epoch 秒 → ミリ秒に直して UTC へ（E6）
                UpdatedAt = DateTimeOffset.FromUnixTimeSeconds(pair.Value.Ts).UtcDateTime,
            })
            .OrderByDescending(entry => entry.UpdatedAt)
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
