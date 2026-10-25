using System.Text;

namespace Moost.Core;

/// <summary>
/// 直近セッション 1 行分の表示データ（conformance E・F 章）。
/// リファレンス実装: <c>packages/core/lib/src/model/recent_session.dart</c>。
/// </summary>
public sealed record RecentSession
{
    /// <summary>フォールバック表題の長さ（runes 基準・サロゲートペアを分断しない）。</summary>
    public const int FallbackTitleLength = 50;

    /// <summary>アダプタ識別子（claude-code / codex / pi / hermes）。</summary>
    public required string AgentId { get; init; }

    public required string SessionId { get; init; }

    /// <summary>復帰コマンドの cd 先。読めなかった場合は空。</summary>
    public required string ProjectPath { get; init; }

    /// <summary>最終プロンプト（表題のフォールバック元）。</summary>
    public required string LastPrompt { get; init; }

    public required DateTime UpdatedAt { get; init; }

    /// <summary>セッション JSONL の ai-title。無ければ null。</summary>
    public string? AiTitle { get; init; }

    /// <summary>
    /// セッションタイトル。ai-title があればそれ、無ければ最終プロンプト先頭 50 文字（F1）。
    /// 数えるのは <b>runes（コードポイント）</b> 単位なので、サロゲートペア（絵文字等）を分断しない。
    /// </summary>
    public string DisplayTitle =>
        string.IsNullOrEmpty(AiTitle) ? FallbackTitle(LastPrompt) : AiTitle;

    public RecentSession WithAiTitle(string? aiTitle) => this with { AiTitle = aiTitle };

    /// <summary>先頭 50 runes に切り詰める。50 runes 以下ならそのまま返す。</summary>
    public static string FallbackTitle(string lastPrompt)
    {
        if (string.IsNullOrEmpty(lastPrompt))
        {
            return string.Empty;
        }

        var runes = lastPrompt.EnumerateRunes();
        var builder = new StringBuilder(lastPrompt.Length);
        var count = 0;
        foreach (var rune in runes)
        {
            if (count == FallbackTitleLength)
            {
                return builder.ToString();
            }

            builder.Append(rune.ToString());
            count++;
        }

        return builder.ToString();
    }
}
