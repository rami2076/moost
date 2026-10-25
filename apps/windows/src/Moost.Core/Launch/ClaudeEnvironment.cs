namespace Moost.Core;

/// <summary>
/// Claude Code が自身のプロセスに設定する内部環境変数の判定・除去（Issue #52 の Windows 版）。
///
/// Moost が <c>claude</c> を子プロセスとして起動する際、Moost 自身のプロセスが
/// これらの変数を（Claude Code のターミナルセッションから開かれた等の経路で）保持していると
/// 子へ継承され、Claude Code が「自分は子セッションだ」と誤認識して transcript の保存を止める。
///
/// macOS 実装は AppleScript に動的な判定を埋め込めないため決め打ちリストを使うが、
/// PowerShell はワイルドカードで環境変数を列挙できるため、
/// <see cref="IsInternalEnvVar"/> と同じ意味（<c>CLAUDE_</c> 接頭辞 + 既知の非接頭辞名）を直接表現する。
/// </summary>
public static class ClaudeEnvironment
{
    /// <summary>内部変数の接頭辞（macOS 実装と同じ判定）。</summary>
    public const string InternalPrefix = "CLAUDE_";

    /// <summary>接頭辞にマッチしない既知の内部変数。</summary>
    public static readonly IReadOnlyList<string> NonPrefixedEnvVarNames = ["CLAUDECODE", "AI_AGENT"];

    /// <summary>
    /// <paramref name="name"/> が Claude Code 関連の内部環境変数とみなせるか。
    /// </summary>
    public static bool IsInternalEnvVar(string name) =>
        name.StartsWith(InternalPrefix, StringComparison.Ordinal)
        || NonPrefixedEnvVarNames.Contains(name, StringComparer.Ordinal);

    /// <summary>
    /// 復帰コマンドの先頭に置く「内部環境変数を消す」プレフィックス。
    ///
    /// <code>Get-ChildItem Env:CLAUDE_*, Env:CLAUDECODE, Env:AI_AGENT -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue; </code>
    ///
    /// 存在しない変数があっても <c>-ErrorAction SilentlyContinue</c> で無視されるため、
    /// 汚染の有無を問わず常に付けてよい（macOS の <c>env -u ...</c> と同じ扱い）。
    /// </summary>
    public static string UnsetPrefix() =>
        "Get-ChildItem Env:" + InternalPrefix + "*, "
        + string.Join(", ", NonPrefixedEnvVarNames.Select(name => "Env:" + name))
        + " -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue; ";
}
