using System.Collections;

namespace Moost.Core;

/// <summary>
/// <c>claude -p</c> によるセッション要約（requirements.md 3.6）。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/ClaudeSummarizer.swift</c>。
///
/// <list type="bullet">
/// <item>モデルは <c>haiku</c> 固定</item>
/// <item>全体要約のフォークセッションが一覧に混ざらないよう、プロンプト先頭にマーカーを入れる</item>
/// <item>Moost 自身が Claude Code 由来の環境変数を持っていると子セッションと誤認識されるため、
/// 子プロセスの環境から<b>取り除く</b>（Issue #52）</item>
/// </list>
/// </summary>
public sealed class ClaudeSummarizer
{
    /// <summary>要約に使うモデル（固定）。</summary>
    public const string Model = "haiku";

    /// <summary>要約用フォークセッションの除外マーカー。</summary>
    public const string Marker = SummaryMarker.Value;

    /// <summary>直近要約のプロンプト（マーカーを先頭に付ける）。</summary>
    public const string RecentPrompt =
        Marker + " 以下は AI コーディングエージェントとの会話の抜粋です。作業内容と現在の状況を簡潔に要約してください。";

    /// <summary>全体要約のプロンプト（マーカーを先頭に付ける）。</summary>
    public const string FullPrompt =
        Marker + " このセッションの作業内容と現在の状況を簡潔に要約してください。";

    private readonly string _claudePath;
    private readonly TimeSpan _timeout;

    public ClaudeSummarizer(string claudePath, TimeSpan? timeout = null)
    {
        _claudePath = claudePath;
        _timeout = timeout ?? TimeSpan.FromMinutes(3);
    }

    /// <summary>抜粋テキストを stdin で渡して要約する（直近要約）。</summary>
    public async Task<string> SummarizeTranscriptAsync(
        string transcript,
        string workingDirectory,
        CancellationToken cancellationToken = default)
    {
        var outcome = await ProcessRunner.RunAsync(
            _claudePath,
            ["-p", "--model", Model, RecentPrompt],
            workingDirectory: workingDirectory,
            stdinText: transcript,
            environment: SanitizedEnvironment(),
            timeout: _timeout,
            cancellationToken: cancellationToken).ConfigureAwait(false);

        return EnsureSuccess(outcome);
    }

    /// <summary>セッションを fork して全体を要約する（全体要約）。</summary>
    public async Task<string> SummarizeFullSessionAsync(
        string sessionId,
        string workingDirectory,
        CancellationToken cancellationToken = default)
    {
        var outcome = await ProcessRunner.RunAsync(
            _claudePath,
            ["-p", "--resume", sessionId, "--fork-session", "--model", Model, FullPrompt],
            workingDirectory: workingDirectory,
            environment: SanitizedEnvironment(),
            timeout: _timeout,
            cancellationToken: cancellationToken).ConfigureAwait(false);

        return EnsureSuccess(outcome);
    }

    private static string EnsureSuccess(ProcessOutcome outcome)
    {
        if (outcome.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(outcome.StdErr) ? outcome.StdOut : outcome.StdErr;
            throw new SummarizeException($"claude が {outcome.ExitCode} で終了しました: {Truncate(detail.Trim())}");
        }

        var summary = outcome.StdOut.Trim();
        if (summary.Length == 0)
        {
            throw new SummarizeException("claude の要約結果が空でした。");
        }

        return summary;
    }

    /// <summary>
    /// 子プロセスから取り除く環境変数（Claude Code の内部変数）。
    /// 値に null を渡すと子プロセスの環境から削除される。
    /// </summary>
    private static Dictionary<string, string?> SanitizedEnvironment()
    {
        var removals = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            if (entry.Key is string name && ClaudeEnvironment.IsInternalEnvVar(name))
            {
                removals[name] = null;
            }
        }

        return removals;
    }

    private static string Truncate(string text) =>
        text.Length <= 2000 ? text : text[..2000] + "…";
}
