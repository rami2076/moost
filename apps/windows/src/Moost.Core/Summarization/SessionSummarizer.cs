namespace Moost.Core;

/// <summary>
/// エージェントを問わずセッション要約を実行するファサード（requirements.md 3.6）。
///
/// <list type="bullet">
/// <item>claude: 直近は「抜粋を stdin に渡して <c>claude -p</c>」、全体は「<c>claude -p --resume --fork-session</c>」</item>
/// <item>codex: 直近は「抜粋を stdin に渡して <c>codex exec --ephemeral</c>」、全体は「<c>codex exec resume</c>」</item>
/// <item>pi / hermes: ヘッドレス要約コマンドを持たないため<b>ローカル抽出の結果をそのまま返す</b>（API 消費ゼロ）</item>
/// </list>
///
/// CLI のパス解決は注入できるようにしてある（UI は設定の上書き → <see cref="AgentPathDetect"/> の順で解決する）。
/// </summary>
public sealed class SessionSummarizer
{
    private readonly SessionSources _sources;
    private readonly Func<string, string?> _resolveCommand;
    private readonly TimeSpan _timeout;

    /// <param name="sources">履歴・セッションの読み取り元。</param>
    /// <param name="resolveCommand">エージェント識別子（claude / codex）→ CLI パス。null なら見つからない扱い。</param>
    /// <param name="timeout">サブプロセスのタイムアウト（既定 3 分）。</param>
    public SessionSummarizer(
        SessionSources sources,
        Func<string, string?>? resolveCommand = null,
        TimeSpan? timeout = null)
    {
        _sources = sources;
        _resolveCommand = resolveCommand ?? (_ => null);
        _timeout = timeout ?? TimeSpan.FromMinutes(3);
    }

    /// <summary>ヘッドレス要約コマンドを持たない（ローカル抽出で済む）エージェントか。</summary>
    public static bool IsLocalOnly(string agentId) =>
        agentId is ResumeCommand.PiAgentId or ResumeCommand.HermesAgentId;

    /// <summary>
    /// 要約を実行してテキストを返す。失敗は <see cref="SummarizeException"/>。
    /// </summary>
    /// <param name="workingDirectory">要約実行時の作業ディレクトリ（空なら指定しない）。</param>
    public async Task<string> SummarizeAsync(
        string agentId,
        string sessionId,
        SummaryScope scope,
        int rallies = 1,
        string workingDirectory = "",
        CancellationToken cancellationToken = default)
    {
        switch (agentId)
        {
            case ResumeCommand.ClaudeAgentId:
            {
                var path = Resolve("claude");
                var summarizer = new ClaudeSummarizer(path, _timeout);

                if (scope == SummaryScope.Full)
                {
                    return await summarizer
                        .SummarizeFullSessionAsync(sessionId, workingDirectory, cancellationToken)
                        .ConfigureAwait(false);
                }

                var transcript = new ClaudeTranscriptExtractor(_sources.ClaudeProjectsDirectory)
                    .Extract(sessionId, rallies);
                return await SummarizerHelpers
                    .RequireTranscript(transcript, summarizer.SummarizeTranscriptAsync, workingDirectory, cancellationToken)
                    .ConfigureAwait(false);
            }

            case ResumeCommand.CodexAgentId:
            {
                var path = Resolve("codex");
                var summarizer = new CodexSummarizer(path, _timeout);

                if (scope == SummaryScope.Full)
                {
                    return await summarizer
                        .SummarizeFullSessionAsync(sessionId, workingDirectory, cancellationToken)
                        .ConfigureAwait(false);
                }

                var transcript = new CodexTranscriptExtractor(
                    new CodexRolloutReader(_sources.CodexSessionsDirectory)).Extract(sessionId, rallies);
                return await SummarizerHelpers
                    .RequireTranscript(transcript, summarizer.SummarizeTranscriptAsync, workingDirectory, cancellationToken)
                    .ConfigureAwait(false);
            }

            case ResumeCommand.PiAgentId:
            {
                var text = new PiTranscriptExtractor(_sources.PiSessionsDirectory)
                    .Extract(sessionId, full: scope == SummaryScope.Full, rallies: rallies);
                return SummarizerHelpers.RequireLocalText(text);
            }

            case ResumeCommand.HermesAgentId:
            {
                var text = new HermesTranscriptExtractor(_sources.HermesDatabase)
                    .Extract(sessionId, full: scope == SummaryScope.Full, rallies: rallies);
                return SummarizerHelpers.RequireLocalText(text);
            }

            default:
                throw new SummarizeException($"不明なエージェントです: {agentId}");
        }
    }

    private string Resolve(string command) =>
        _resolveCommand(command)
        ?? throw new SummarizeException(
            $"{command} が見つかりません。設定でパスを指定するか、PATH の通った環境で起動してください。");
}

/// <summary>要約まわりの共通チェック。</summary>
internal static class SummarizerHelpers
{
    /// <summary>抜粋が取れない場合（期限切れ・ファイル欠落）は要約せずに失敗させる。</summary>
    public static async Task<string> RequireTranscript(
        string? transcript,
        Func<string, string, CancellationToken, Task<string>> summarize,
        string workingDirectory,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(transcript))
        {
            throw new SummarizeException(
                "セッションの会話を読み取れませんでした。セッションが期限切れ（cleanupPeriodDays）の可能性があります。");
        }

        return await summarize(transcript, workingDirectory, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>ローカル抽出の結果が空なら失敗として扱う（pi / hermes）。</summary>
    public static string RequireLocalText(string text) =>
        string.IsNullOrWhiteSpace(text)
            ? throw new SummarizeException(
                "セッションの会話を読み取れませんでした。セッションが期限切れ（cleanupPeriodDays）の可能性があります。")
            : text;
}
