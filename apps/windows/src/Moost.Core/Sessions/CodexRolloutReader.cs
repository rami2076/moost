using System.Text.RegularExpressions;

namespace Moost.Core;

/// <summary>
/// <c>%USERPROFILE%\.codex\sessions\</c> 配下の rollout JSONL を扱う。
/// リファレンス実装: <c>packages/core/lib/src/agent/codex/codex_rollout_reader.dart</c>。
///
/// セッション本体は <c>sessions/YYYY/MM/DD/rollout-&lt;日時&gt;-&lt;sessionId&gt;.jsonl</c>。
/// 日付ディレクトリの構造には依存せず、「ファイル名末尾が <c>-&lt;sessionId&gt;.jsonl</c>」という
/// 性質だけを使って再帰走査で見つける（Claude の <see cref="AiTitleReader"/> と同じ方針）。
/// </summary>
public sealed partial class CodexRolloutReader
{
    private const int MaxHeadLines = 10;

    private readonly string _sessionsDirectory;

    public CodexRolloutReader(string sessionsDirectory)
    {
        _sessionsDirectory = sessionsDirectory;
    }

    [GeneratedRegex(@"rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$")]
    private static partial Regex RolloutNamePattern { get; }

    /// <summary>
    /// sessionId → rollout ファイルの索引を作る。
    /// 同一 sessionId の rollout が複数ある場合（resume 等）は、
    /// ファイル名に日時が入っている性質を使い辞書順で最新を採用する。
    /// </summary>
    public IReadOnlyDictionary<string, string> Scan()
    {
        var index = new Dictionary<string, string>(StringComparer.Ordinal);
        if (!Directory.Exists(_sessionsDirectory))
        {
            return index;
        }

        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(_sessionsDirectory, "*.jsonl", SearchOption.AllDirectories);
        }
        catch (IOException)
        {
            return index;
        }
        catch (UnauthorizedAccessException)
        {
            return index;
        }

        foreach (var file in files)
        {
            var name = Path.GetFileName(file);
            var match = RolloutNamePattern.Match(name);
            if (!match.Success)
            {
                continue;
            }

            var sessionId = match.Groups[1].Value;
            if (!index.TryGetValue(sessionId, out var existing)
                || string.CompareOrdinal(Path.GetFileName(existing), name) < 0)
            {
                index[sessionId] = file;
            }
        }

        return index;
    }

    /// <summary>
    /// rollout 先頭の <c>session_meta</c> 行からセッションの作業ディレクトリを返す。
    /// 見つからない・読めない場合は null。
    /// </summary>
    public string? ReadCwd(string rolloutFile)
    {
        try
        {
            using var reader = new StreamReader(rolloutFile);
            for (var count = 0; count < MaxHeadLines; count++)
            {
                var line = reader.ReadLine();
                if (line is null)
                {
                    break;
                }

                if (!line.Contains("\"session_meta\"", StringComparison.Ordinal))
                {
                    continue;
                }

                if (!JsonlLine.TryParseObject(line, out var json)
                    || !JsonRead.TryString(json, "type", out var type)
                    || type != "session_meta"
                    || json["payload"] is not System.Text.Json.Nodes.JsonObject payload
                    || !JsonRead.TryString(payload, "cwd", out var cwd))
                {
                    continue;
                }

                return cwd;
            }
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }

        return null;
    }
}
