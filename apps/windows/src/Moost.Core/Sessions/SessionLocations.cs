namespace Moost.Core;

/// <summary>
/// エージェントの履歴・セッションの既定の置き場所（Windows）。
///
/// macOS の <c>~/.claude</c> 等に対応する。Windows ではネイティブ版 CLI の置く場所
/// （<c>%USERPROFILE%\.claude</c> 等）を使う。WSL 側に CLI がある場合の扱いは未対応。
/// </summary>
public static class SessionLocations
{
    public static string ClaudeHistoryFile(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".claude", "history.jsonl");

    public static string ClaudeProjectsDirectory(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".claude", "projects");

    public static string CodexHistoryFile(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".codex", "history.jsonl");

    public static string CodexSessionsDirectory(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".codex", "sessions");

    public static string PiSessionsDirectory(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".pi", "agent", "sessions");

    public static string HermesStateDb(string? userProfile = null) =>
        Path.Combine(Home(userProfile), ".hermes", "state.db");

    private static string Home(string? userProfile) =>
        userProfile ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
}

/// <summary>
/// JSONL の 1 行を緩く読むための小さなヘルパー。
/// 壊れた行・空行はすべて <c>null</c> として扱い、呼び出し側がスキップできるようにする（E1）。
/// </summary>
internal static class JsonlLine
{
    /// <summary>行を JSON オブジェクトとして読む。壊れていれば false。</summary>
    public static bool TryParseObject(string? line, out System.Text.Json.Nodes.JsonObject json)
    {
        json = null!;
        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        try
        {
            if (System.Text.Json.Nodes.JsonNode.Parse(line) is System.Text.Json.Nodes.JsonObject parsed)
            {
                json = parsed;
                return true;
            }
        }
        catch (System.Text.Json.JsonException)
        {
            // 内部フォーマット変更で落ちないよう、壊れた行はスキップする
        }

        return false;
    }

    /// <summary>ファイルを行単位で読む。存在しなければ空（読み取り失敗は空扱い）。</summary>
    public static IReadOnlyList<string> ReadLines(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return [];
        }

        try
        {
            return File.ReadAllLines(filePath);
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
