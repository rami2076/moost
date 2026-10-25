using System.Text;
using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// セッション JSONL の末尾から最新の ai-title を取り出す（conformance F2）。
/// リファレンス実装: <c>packages/core/lib/src/agent/claude_code/ai_title_reader.dart</c>。
///
/// <list type="bullet">
/// <item>セッション JSONL は数十 MB になりうるため全読みせず、末尾チャンクだけ読む</item>
/// <item>逆順走査で最初にヒットしたものが最新（タイトルは会話中に更新される）</item>
/// <item><c>"ai-title"</c> を含むが JSON でない行はスキップして続行する</item>
/// </list>
/// </summary>
public sealed class AiTitleReader
{
    /// <summary>末尾から読む既定のバイト数（64KB）。</summary>
    public const int DefaultTailBytes = 64 * 1024;

    private readonly string _projectsDirectory;
    private readonly int _tailBytes;

    public AiTitleReader(string projectsDirectory, int tailBytes = DefaultTailBytes)
    {
        _projectsDirectory = projectsDirectory;
        _tailBytes = tailBytes;
    }

    public string? LatestAiTitle(string sessionId)
    {
        var sessionFile = FindSessionFile(sessionId);
        if (sessionFile is null)
        {
            return null;
        }

        if (!TryReadTail(sessionFile, out var text, out var truncated))
        {
            return null;
        }

        // 末尾チャンクの先頭が途中で切れた行なら不完全なので、その行は捨てる
        if (truncated)
        {
            var newline = text.IndexOf('\n', StringComparison.Ordinal);
            if (newline >= 0)
            {
                text = text[(newline + 1)..];
            }
        }

        var lines = text.Split('\n');
        for (var index = lines.Length - 1; index >= 0; index--)
        {
            var line = lines[index];

            // 安いフィルタを先にかけ、含む行だけ JSON デコードする
            if (!line.Contains("\"ai-title\"", StringComparison.Ordinal))
            {
                continue;
            }

            if (!JsonlLine.TryParseObject(line, out var json)
                || !JsonRead.TryString(json, "type", out var type)
                || type != "ai-title"
                || !JsonRead.TryString(json, "aiTitle", out var title)
                || title.Length == 0)
            {
                continue;
            }

            return title;
        }

        return null;
    }

    /// <summary>
    /// ディレクトリ名のエンコード規則には依存せず、ファイル名（<c>&lt;sessionId&gt;.jsonl</c>）の
    /// 一意性だけを使う（design.md 3.2）。
    /// </summary>
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

    /// <summary>末尾チャンクを UTF-8 として読む。途中で切れたマルチバイトは置換文字になるが、
    /// その行は <paramref name="truncated"/> により捨てるので影響しない。</summary>
    private bool TryReadTail(string filePath, out string text, out bool truncated)
    {
        text = string.Empty;
        truncated = false;

        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var length = stream.Length;
            var start = Math.Max(0, length - _tailBytes);
            truncated = start > 0;

            stream.Seek(start, SeekOrigin.Begin);
            var buffer = new byte[length - start];
            stream.ReadExactly(buffer);

            text = Encoding.UTF8.GetString(buffer);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
