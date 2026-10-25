using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// pi セッション 1 件分の抽出結果。
/// </summary>
public sealed record PiSessionEntry
{
    public required string SessionId { get; init; }

    public required string ProjectPath { get; init; }

    public required string LastPrompt { get; init; }

    public required DateTime UpdatedAt { get; init; }
}

/// <summary>
/// pi のセッション保存（<c>%USERPROFILE%\.pi\agent\sessions\&lt;cwd毎&gt;\&lt;ts&gt;_&lt;id&gt;.jsonl</c>）を読む。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/PiSessionHistoryReader.swift</c>。
///
/// JSONL の先頭行にセッションヘッダ（<c>type: session</c>）があり <c>id</c> / <c>cwd</c> /
/// 開始時刻を持つ。以降はイベント行で、<c>type: message</c> の <c>message.role == user</c> の
/// テキストが会話の入口になる。壊れた行・読めないファイルはスキップする。
/// </summary>
public sealed class PiSessionReader
{
    private readonly string _sessionsDirectory;

    public PiSessionReader(string sessionsDirectory)
    {
        _sessionsDirectory = sessionsDirectory;
    }

    /// <summary>既定の保存先（<c>%USERPROFILE%\.pi\agent\sessions</c>）を使う。</summary>
    public static PiSessionReader DefaultLocation(string? userProfile = null) =>
        new(SessionLocations.PiSessionsDirectory(userProfile));

    /// <summary>
    /// 全セッションを新しい順で返す（全ファイルを走査するため、ここでは件数を切らない）。
    /// </summary>
    public IReadOnlyList<PiSessionEntry> RecentSessions(int limit = 20)
    {
        if (!Directory.Exists(_sessionsDirectory))
        {
            return [];
        }

        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(_sessionsDirectory, "*.jsonl", SearchOption.AllDirectories);
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }

        var entries = new List<PiSessionEntry>();
        foreach (var file in files.OrderBy(path => path, StringComparer.Ordinal))
        {
            var entry = ScanFile(file);
            if (entry is not null)
            {
                entries.Add(entry);
            }
        }

        return entries
            .OrderByDescending(entry => entry.UpdatedAt)
            .Take(limit)
            .ToArray();
    }

    /// <summary>
    /// 1 ファイルからヘッダ・最終プロンプト・更新時刻を読む。読めなければ null。
    ///
    /// JSONL は時系列で追記されるため、末尾から逆順に走査し
    /// 「最後のユーザー発言」と「最新のタイムスタンプ」が揃った時点で打ち切る。
    /// </summary>
    private static PiSessionEntry? ScanFile(string filePath)
    {
        string[] lines;
        try
        {
            lines = File.ReadAllLines(filePath);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        if (lines.Length == 0 || !TryParseHeader(lines[0], out var header))
        {
            return null;
        }

        var lastUserText = string.Empty;
        var newest = header.Timestamp;

        for (var index = lines.Length - 1; index >= 1; index--)
        {
            if (lastUserText.Length > 0 && newest != header.Timestamp)
            {
                break;
            }

            if (!JsonlLine.TryParseObject(lines[index], out var json)
                || !JsonRead.TryString(json, "type", out var type)
                || type != "message")
            {
                continue;
            }

            if (JsonRead.TryString(json, "timestamp", out var timestampText)
                && TryParseIso(timestampText, out var timestamp)
                && timestamp > newest)
            {
                newest = timestamp;
            }

            if (lastUserText.Length == 0 && TryUserText(json, out var userText) && userText.Length > 0)
            {
                lastUserText = userText;
            }
        }

        return new PiSessionEntry
        {
            SessionId = header.Id,
            ProjectPath = header.Cwd,
            LastPrompt = lastUserText,
            UpdatedAt = newest,
        };
    }

    private static bool TryParseHeader(string line, out (string Id, string Cwd, DateTime Timestamp) header)
    {
        header = default;

        if (!JsonlLine.TryParseObject(line, out var json)
            || !JsonRead.TryString(json, "type", out var type)
            || type != "session"
            || !JsonRead.TryString(json, "id", out var id)
            || id.Length == 0)
        {
            return false;
        }

        var cwd = JsonRead.TryString(json, "cwd", out var parsedCwd) ? parsedCwd : string.Empty;
        var timestamp = JsonRead.TryString(json, "timestamp", out var text) && TryParseIso(text, out var parsed)
            ? parsed
            : DateTime.UnixEpoch;

        header = (id, cwd, timestamp);
        return true;
    }

    /// <summary>
    /// <c>message.role == "user"</c> の <c>content</c> 配列から <c>type: "text"</c> の
    /// <c>text</c> を連結して返す（空要素は落とす）。
    /// </summary>
    private static bool TryUserText(JsonObject json, out string text)
    {
        text = string.Empty;

        if (json["message"] is not JsonObject message
            || !JsonRead.TryString(message, "role", out var role)
            || role != "user"
            || message["content"] is not JsonArray content)
        {
            return false;
        }

        var parts = new List<string>();
        foreach (var node in content)
        {
            if (node is JsonObject part
                && JsonRead.TryString(part, "type", out var partType)
                && partType == "text"
                && JsonRead.TryString(part, "text", out var partText))
            {
                var trimmed = partText.Trim();
                if (trimmed.Length > 0)
                {
                    parts.Add(trimmed);
                }
            }
        }

        text = string.Join(" ", parts);
        return text.Length > 0;
    }

    private static bool TryParseIso(string value, out DateTime timestamp) =>
        IsoUtc.TryParse(value, out timestamp);
}
