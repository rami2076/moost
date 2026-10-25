namespace Moost.Core;

/// <summary>
/// 復帰・新規セッションのコマンドを組み立てる（conformance G1 / G2・Windows 版）。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/Launch.swift</c> の <c>ResumeCommand</c>。
///
/// POSIX の <c>cd 'x' &amp;&amp; agent ...</c> に対し、Windows は
/// <c>Set-Location -LiteralPath 'x'; agent ...</c> を使う。
/// <list type="bullet">
/// <item><c>&amp;&amp;</c> は PowerShell 7 以降にしか無いため、既定の Windows PowerShell 5.1 でも動く <c>;</c> を使う</item>
/// <item><c>cd</c>（= <c>Set-Location -Path</c>）は <c>[</c> <c>]</c> <c>*</c> をワイルドカードとして解釈するため、
/// <c>-LiteralPath</c> を使う</item>
/// </list>
/// </summary>
public static class ResumeCommand
{
    /// <summary>アダプタ識別子（リファレンス実装の agentId と一致させる）。</summary>
    public const string ClaudeAgentId = "claude-code";
    public const string CodexAgentId = "codex";
    public const string PiAgentId = "pi";
    public const string HermesAgentId = "hermes";

    /// <summary>
    /// 復帰先ディレクトリへ移動する部分。空パスなら何も付けない。
    /// </summary>
    public static string SetLocation(string? projectPath) =>
        string.IsNullOrEmpty(projectPath)
            ? string.Empty
            : "Set-Location -LiteralPath " + PowerShellQuote.Quote(projectPath) + "; ";

    /// <summary>claude 用。claude の直前で内部環境変数を消す（Issue #52）。</summary>
    public static string ClaudeResume(string? projectPath, string sessionId) =>
        SetLocation(projectPath)
        + ClaudeEnvironment.UnsetPrefix()
        + "claude --resume " + PowerShellQuote.Quote(sessionId);

    public static string ClaudeNewSession(string? projectPath) =>
        SetLocation(projectPath) + ClaudeEnvironment.UnsetPrefix() + "claude";

    /// <summary>
    /// codex 用。session_meta が読めなかったセッションは projectPath が空になりうる。
    /// resume 自体はどこからでも効くので cd を付けない。
    /// </summary>
    public static string CodexResume(string? projectPath, string sessionId) =>
        SetLocation(projectPath) + "codex resume " + PowerShellQuote.Quote(sessionId);

    public static string CodexNewSession(string? projectPath) =>
        SetLocation(projectPath) + "codex";

    /// <summary>pi 用。provider / model が指定されていればフラグを付ける（Issue #68）。</summary>
    public static string PiResume(
        string? projectPath,
        string sessionId,
        string? provider = null,
        string? model = null) =>
        PiCommand("pi --session " + PowerShellQuote.Quote(sessionId), projectPath, provider, model);

    public static string PiNewSession(
        string? projectPath,
        string? provider = null,
        string? model = null) =>
        PiCommand("pi", projectPath, provider, model);

    private static string PiCommand(
        string prefix,
        string? projectPath,
        string? provider,
        string? model)
    {
        var flags = new List<string>();
        if (!string.IsNullOrEmpty(provider))
        {
            flags.Add("--provider " + PowerShellQuote.Quote(provider));
        }

        if (!string.IsNullOrEmpty(model))
        {
            flags.Add("--model " + PowerShellQuote.Quote(model));
        }

        var command = flags.Count == 0 ? prefix : prefix + " " + string.Join(" ", flags);
        return SetLocation(projectPath) + command;
    }

    /// <summary>hermes 用。<c>hermes chat --resume &lt;id&gt;</c>（記録済み cwd へ自動復帰する）。</summary>
    public static string HermesResume(string? projectPath, string sessionId) =>
        SetLocation(projectPath) + "hermes chat --resume " + PowerShellQuote.Quote(sessionId);

    public static string HermesNewSession(string? projectPath) =>
        SetLocation(projectPath) + "hermes chat";

    /// <summary>
    /// アダプタ識別子（<c>Memo.Agent</c> / <c>RecentSession.AgentId</c>）から復帰コマンドを組み立てる。
    /// 未知のエージェントは null（UI 側は「不明な agent」を表示する）。
    /// </summary>
    public static string? Resume(
        string agent,
        string? projectPath,
        string sessionId,
        string? provider = null,
        string? model = null) =>
        agent switch
        {
            ClaudeAgentId => ClaudeResume(projectPath, sessionId),
            CodexAgentId => CodexResume(projectPath, sessionId),
            PiAgentId => PiResume(projectPath, sessionId, provider, model),
            HermesAgentId => HermesResume(projectPath, sessionId),
            _ => null,
        };

    /// <summary>アダプタ識別子から新規セッションのコマンドを組み立てる（ADR-004）。</summary>
    public static string? NewSession(
        string agent,
        string? projectPath,
        string? provider = null,
        string? model = null) =>
        agent switch
        {
            ClaudeAgentId => ClaudeNewSession(projectPath),
            CodexAgentId => CodexNewSession(projectPath),
            PiAgentId => PiNewSession(projectPath, provider, model),
            HermesAgentId => HermesNewSession(projectPath),
            _ => null,
        };
}
