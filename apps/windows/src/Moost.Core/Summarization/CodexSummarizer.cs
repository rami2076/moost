namespace Moost.Core;

/// <summary>
/// <c>codex exec</c> によるセッション要約。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/CodexSummarizer.swift</c>。
///
/// <list type="bullet">
/// <item><c>--ephemeral</c> でセッションを永続化しない（rollout も history も残さない）</item>
/// <item><c>codex exec</c> の stdout は進捗ログを含むため、結果は
/// <c>--output-last-message</c> のファイルから取る（無ければ stdout にフォールバック）</item>
/// <item>直近要約は「プロンプト引数 + stdin」で抜粋を渡す仕様を使う</item>
/// </list>
/// </summary>
public sealed class CodexSummarizer
{
    /// <summary>要約用の除外マーカー（ClaudeSummarizer と同じ文字列）。</summary>
    public const string Marker = SummaryMarker.Value;

    public const string RecentPrompt =
        Marker + " 以下は AI コーディングエージェントとの会話の抜粋です。作業内容と現在の状況を簡潔に要約してください。";

    public const string FullPrompt =
        Marker + " このセッションの作業内容と現在の状況を簡潔に要約してください。";

    private readonly string _codexPath;
    private readonly TimeSpan _timeout;

    public CodexSummarizer(string codexPath, TimeSpan? timeout = null)
    {
        _codexPath = codexPath;
        _timeout = timeout ?? TimeSpan.FromMinutes(3);
    }

    /// <summary>抜粋テキストを stdin で渡して要約する（直近要約）。</summary>
    public async Task<string> SummarizeTranscriptAsync(
        string transcript,
        string workingDirectory,
        CancellationToken cancellationToken = default)
    {
        return await RunAsync(
            outputFile => ["exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                "--output-last-message", outputFile, RecentPrompt],
            workingDirectory,
            transcript,
            cancellationToken).ConfigureAwait(false);
    }

    /// <summary>セッションを ephemeral で resume して全体を要約する（全体要約）。</summary>
    public async Task<string> SummarizeFullSessionAsync(
        string sessionId,
        string workingDirectory,
        CancellationToken cancellationToken = default)
    {
        return await RunAsync(
            outputFile => ["exec", "resume", sessionId, "--ephemeral", "--skip-git-repo-check",
                "--output-last-message", outputFile, FullPrompt],
            workingDirectory,
            stdinText: null,
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<string> RunAsync(
        Func<string, string[]> buildArguments,
        string workingDirectory,
        string? stdinText,
        CancellationToken cancellationToken)
    {
        var tempDirectory = Path.Combine(Path.GetTempPath(), "moost_codex_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDirectory);

        try
        {
            var outputFile = Path.Combine(tempDirectory, "last_message.txt");
            var outcome = await ProcessRunner.RunAsync(
                _codexPath,
                buildArguments(outputFile),
                workingDirectory: workingDirectory,
                stdinText: stdinText,
                timeout: _timeout,
                cancellationToken: cancellationToken).ConfigureAwait(false);

            if (outcome.ExitCode != 0)
            {
                var detail = string.IsNullOrWhiteSpace(outcome.StdErr) ? outcome.StdOut : outcome.StdErr;
                throw new SummarizeException($"codex が {outcome.ExitCode} で終了しました: {Truncate(detail.Trim())}");
            }

            // 進捗ログを避けるため、まず --output-last-message のファイルを見る
            if (File.Exists(outputFile))
            {
                var fromFile = File.ReadAllText(outputFile).Trim();
                if (fromFile.Length > 0)
                {
                    return fromFile;
                }
            }

            var fallback = outcome.StdOut.Trim();
            if (fallback.Length == 0)
            {
                throw new SummarizeException("codex の要約結果が空でした。");
            }

            return fallback;
        }
        finally
        {
            TryDeleteDirectory(tempDirectory);
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            Directory.Delete(path, recursive: true);
        }
        catch (IOException)
        {
            // 一時ディレクトリの掃除失敗は要約結果に影響させない
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static string Truncate(string text) =>
        text.Length <= 2000 ? text : text[..2000] + "…";
}
