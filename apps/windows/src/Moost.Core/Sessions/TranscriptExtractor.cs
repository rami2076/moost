using System.Text;
using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>会話抜粋の 1 ラリー（ユーザー発言 + 続く応答群）。</summary>
internal sealed class Rally
{
    public Rally(string userText) => UserText = userText;

    public string UserText { get; }

    public List<(string Role, string Text)> Followups { get; } = [];

    /// <summary><c>User:</c> / <c>Assistant:</c> 形式で描画する（リファレンス実装と同形）。</summary>
    public static string Render(IEnumerable<Rally> rallies)
    {
        var builder = new StringBuilder();
        foreach (var rally in rallies)
        {
            builder.Append("User: ").Append(rally.UserText).Append('\n');
            foreach (var (role, text) in rally.Followups)
            {
                builder.Append(role).Append(": ").Append(text).Append('\n');
            }

            builder.Append('\n');
        }

        return builder.ToString().Trim();
    }
}

/// <summary>
/// claude セッション JSONL から直近 N ラリーの会話抜粋を取り出す。
/// リファレンス実装: <c>ClaudeTranscriptExtractor</c>（Swift）。
/// </summary>
public sealed class ClaudeTranscriptExtractor
{
    private readonly string _projectsDirectory;

    public ClaudeTranscriptExtractor(string projectsDirectory)
    {
        _projectsDirectory = projectsDirectory;
    }

    /// <summary>抜粋を返す。セッションファイルが無い・発言が無ければ null。</summary>
    public string? Extract(string sessionId, int rallies = 1)
    {
        var file = FindSessionFile(sessionId);
        if (file is null)
        {
            return null;
        }

        var collected = new List<Rally>();
        foreach (var line in JsonlLine.ReadLines(file))
        {
            if (!TryParseMessage(line, out var role, out var text))
            {
                continue;
            }

            if (role == "user")
            {
                collected.Add(new Rally(text));
                if (collected.Count > rallies)
                {
                    // メモリを抑えるため保持は直近分だけにする
                    collected.RemoveAt(0);
                }
            }
            else if (collected.Count > 0)
            {
                collected[^1].Followups.Add(("Assistant", text));
            }
        }

        return collected.Count == 0 ? null : Rally.Render(collected);
    }

    private string? FindSessionFile(string sessionId)
    {
        if (!Directory.Exists(_projectsDirectory))
        {
            return null;
        }

        IEnumerable<string> directories;
        try
        {
            directories = Directory.EnumerateDirectories(_projectsDirectory);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        var fileName = sessionId + ".jsonl";
        foreach (var directory in directories)
        {
            var candidate = Path.Combine(directory, fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static bool TryParseMessage(string line, out string role, out string text)
    {
        role = string.Empty;
        text = string.Empty;

        // 安いフィルタ: user / assistant メッセージ行だけを対象にする
        if (!line.Contains("\"type\":\"user\"", StringComparison.Ordinal)
            && !line.Contains("\"type\":\"assistant\"", StringComparison.Ordinal))
        {
            return false;
        }

        if (!JsonlLine.TryParseObject(line, out var json)
            || (json["isSidechain"] is JsonValue sidechain && sidechain.TryGetValue<bool>(out var isSidechain) && isSidechain)
            || !JsonRead.TryString(json, "type", out var type)
            || (type != "user" && type != "assistant")
            || json["message"] is not JsonObject message)
        {
            return false;
        }

        role = type;
        return TryContentText(message["content"], blockType: "text", out text);
    }

    /// <summary>
    /// <c>content</c> は文字列、またはブロック配列（<c>{"type":"text","text":...}</c>）。
    /// </summary>
    internal static bool TryContentText(JsonNode? content, string blockType, out string text)
    {
        text = string.Empty;

        if (content is JsonValue value && value.TryGetValue<string>(out var raw) && raw is not null)
        {
            text = raw;
            return true;
        }

        if (content is not JsonArray blocks)
        {
            return false;
        }

        var parts = new List<string>();
        foreach (var node in blocks)
        {
            if (node is JsonObject block
                && JsonRead.TryString(block, "type", out var type)
                && type == blockType
                && JsonRead.TryString(block, "text", out var part))
            {
                parts.Add(part);
            }
        }

        if (parts.Count == 0)
        {
            return false;
        }

        text = string.Join("\n", parts);
        return true;
    }
}

/// <summary>
/// codex rollout JSONL から直近 N ラリーの会話抜粋を取り出す。
/// リファレンス実装: <c>CodexTranscriptExtractor</c>（Swift）。
/// </summary>
public sealed class CodexTranscriptExtractor
{
    /// <summary>codex が user ロールで記録するシステム由来テキストの既知プレフィックス。</summary>
    private static readonly string[] SystemUserPrefixes =
    [
        "<environment_context>",
        "<user_instructions>",
        "<user_action>",
        "<turn_aborted>",
        "<permissions",
    ];

    private readonly CodexRolloutReader _rolloutReader;

    public CodexTranscriptExtractor(CodexRolloutReader rolloutReader)
    {
        _rolloutReader = rolloutReader;
    }

    public string? Extract(string sessionId, int rallies = 1)
    {
        var index = _rolloutReader.Scan();
        if (!index.TryGetValue(sessionId, out var file))
        {
            return null;
        }

        var collected = new List<Rally>();
        foreach (var line in JsonlLine.ReadLines(file))
        {
            if (!TryParseMessage(line, out var role, out var text))
            {
                continue;
            }

            if (role == "user")
            {
                collected.Add(new Rally(text));
                if (collected.Count > rallies)
                {
                    collected.RemoveAt(0);
                }
            }
            else if (collected.Count > 0)
            {
                collected[^1].Followups.Add(("Assistant", text));
            }
        }

        return collected.Count == 0 ? null : Rally.Render(collected);
    }

    private static bool TryParseMessage(string line, out string role, out string text)
    {
        role = string.Empty;
        text = string.Empty;

        if (!line.Contains("\"type\":\"response_item\"", StringComparison.Ordinal)
            && !line.Contains("\"type\":\"message\"", StringComparison.Ordinal))
        {
            return false;
        }

        if (!JsonlLine.TryParseObject(line, out var json)
            || !JsonRead.TryString(json, "type", out var type)
            || type != "response_item"
            || json["payload"] is not JsonObject payload
            || !JsonRead.TryString(payload, "type", out var payloadType)
            || payloadType != "message"
            || !JsonRead.TryString(payload, "role", out var payloadRole)
            || (payloadRole != "user" && payloadRole != "assistant")
            || !ClaudeTranscriptExtractor.TryContentText(payload["content"], "input_text", out var inputText)
               && !ClaudeTranscriptExtractor.TryContentText(payload["content"], "output_text", out inputText))
        {
            return false;
        }

        // システム由来のコンテキストは user ロールで記録されるため除外する
        if (payloadRole == "user"
            && SystemUserPrefixes.Any(prefix => inputText.StartsWith(prefix, StringComparison.Ordinal)))
        {
            return false;
        }

        role = payloadRole;
        text = inputText;
        return true;
    }
}

/// <summary>
/// pi セッション JSONL から要約用のプレーンテキストを組み立てる。
/// pi はヘッドレス要約コマンドを持たないため、抽出結果をそのまま要約として返す（API 消費ゼロ）。
/// </summary>
public sealed class PiTranscriptExtractor
{
    private readonly string _sessionsDirectory;

    public PiTranscriptExtractor(string sessionsDirectory)
    {
        _sessionsDirectory = sessionsDirectory;
    }

    /// <summary>
    /// セッションのやり取りをテキスト化して返す（見つからなければ空文字列）。
    /// <paramref name="full"/> が false なら末尾 <c>rallies * 2</c> メッセージ、true なら全体。
    /// </summary>
    public string Extract(string sessionId, bool full = false, int rallies = 1)
    {
        var file = FindSessionFile(sessionId);
        if (file is null)
        {
            return string.Empty;
        }

        var messages = new List<(string Role, string Text)>();
        foreach (var line in JsonlLine.ReadLines(file))
        {
            if (TryParseMessage(line, out var role, out var text))
            {
                messages.Add((role, text));
            }
        }

        if (messages.Count == 0)
        {
            return string.Empty;
        }

        var limit = rallies * 2;
        var selected = full || messages.Count <= limit
            ? messages
            : messages.Skip(messages.Count - limit).ToList();

        var builder = new StringBuilder();
        foreach (var (role, text) in selected)
        {
            var trimmed = text.Trim();
            if (trimmed.Length == 0)
            {
                continue;
            }

            builder.Append(role == "user" ? "User: " : "Assistant: ").Append(trimmed).Append("\n\n");
        }

        return builder.ToString().Trim();
    }

    private string? FindSessionFile(string sessionId)
    {
        if (!Directory.Exists(_sessionsDirectory))
        {
            return null;
        }

        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(_sessionsDirectory, "*.jsonl", SearchOption.AllDirectories);
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        var candidates = new List<string>();
        foreach (var file in files)
        {
            if (Path.GetFileName(file).Contains("_" + sessionId + ".jsonl", StringComparison.Ordinal))
            {
                return file;
            }

            candidates.Add(file);
        }

        // フォールバック: ヘッダの id と照合する
        foreach (var file in candidates)
        {
            var lines = JsonlLine.ReadLines(file);
            if (lines.Count == 0 || !JsonlLine.TryParseObject(lines[0], out var header))
            {
                continue;
            }

            if (JsonRead.TryString(header, "type", out var type) && type == "session"
                && JsonRead.TryString(header, "id", out var id) && id == sessionId)
            {
                return file;
            }
        }

        return null;
    }

    private static bool TryParseMessage(string line, out string role, out string text)
    {
        role = string.Empty;
        text = string.Empty;

        if (!JsonlLine.TryParseObject(line, out var json)
            || !JsonRead.TryString(json, "type", out var type)
            || type != "message"
            || json["message"] is not JsonObject message
            || !JsonRead.TryString(message, "role", out var messageRole)
            || (messageRole != "user" && messageRole != "assistant")
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

        if (parts.Count == 0)
        {
            return false;
        }

        role = messageRole;
        text = string.Join("\n", parts);
        return true;
    }
}
