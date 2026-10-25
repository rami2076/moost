using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 要約のサブプロセス実行（#101 後半）。実 CLI の代わりに偽の <c>.cmd</c> を使う。
/// </summary>
public class SummarizerTests
{
    private const string Transcript = "User: q1\nAssistant: a1";

    [Fact]
    public async Task Claude_Recent_PassesTranscriptOnStdin_AndSanitizesInternalEnvVars()
    {
        using var dir = new TempDir();
        var claude = FakeCli.ClaudeEcho(dir);

        const string variable = "CLAUDE_CODE_CHILD_SESSION";
        var original = Environment.GetEnvironmentVariable(variable);
        Environment.SetEnvironmentVariable(variable, "leaked");
        string summary;
        try
        {
            summary = await new ClaudeSummarizer(claude, TimeSpan.FromSeconds(60))
                .SummarizeTranscriptAsync(Transcript, dir.Path);
        }
        finally
        {
            Environment.SetEnvironmentVariable(variable, original);
        }

        // 引数（モデルは haiku 固定・マーカーが先頭）
        // 子プロセスの stdout は OEM コードページなので、日本語は引数ファイル（UTF-8）で見る
        var args = File.ReadAllText(Path.Combine(dir.Path, "args.txt"));
        Assert.StartsWith("-p|--model|haiku|", args, StringComparison.Ordinal);
        Assert.Contains(ClaudeSummarizer.Marker, args, StringComparison.Ordinal);

        // 内部環境変数は子プロセスから取り除かれている（stdout は ASCII）
        Assert.Contains("ENV=", summary, StringComparison.Ordinal);
        Assert.DoesNotContain("leaked", summary, StringComparison.Ordinal);

        // stdin に抜粋がそのまま渡っている
        Assert.Equal(Transcript, File.ReadAllText(Path.Combine(dir.Path, "stdin.txt")));
    }

    [Fact]
    public async Task Claude_Full_PassesResumeAndForkFlags()
    {
        using var dir = new TempDir();
        var summary = await new ClaudeSummarizer(FakeCli.ClaudeEcho(dir), TimeSpan.FromSeconds(60))
            .SummarizeFullSessionAsync("s-1", dir.Path);

        var args = File.ReadAllText(Path.Combine(dir.Path, "args.txt"));
        Assert.StartsWith("-p|--resume|s-1|--fork-session|--model|haiku|", args, StringComparison.Ordinal);
        Assert.Contains(ClaudeSummarizer.Marker, args, StringComparison.Ordinal);
        Assert.Contains("ENV=", summary, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Codex_Recent_UsesOutputLastMessageFile_AndEphemeralFlags()
    {
        using var dir = new TempDir();
        var summary = await new CodexSummarizer(FakeCli.CodexEchoArgs(dir), TimeSpan.FromSeconds(60))
            .SummarizeTranscriptAsync(Transcript, dir.Path);

        // stdout の進捗ログではなく --output-last-message のファイルが採用される
        Assert.StartsWith("ARGS=exec|--ephemeral|--skip-git-repo-check|--sandbox|read-only|--output-last-message|",
            summary, StringComparison.Ordinal);
        Assert.Contains("|[Moost要約]", summary, StringComparison.Ordinal);
        Assert.DoesNotContain("progress log", summary, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Codex_Full_PassesResumeSubcommand()
    {
        using var dir = new TempDir();
        var summary = await new CodexSummarizer(FakeCli.CodexEchoArgs(dir), TimeSpan.FromSeconds(60))
            .SummarizeFullSessionAsync("s-9", dir.Path);

        Assert.StartsWith("ARGS=exec|resume|s-9|--ephemeral|--skip-git-repo-check|",
            summary, StringComparison.Ordinal);
    }

    [Fact]
    public async Task NonZeroExit_ThrowsWithStderr()
    {
        using var dir = new TempDir();
        var summarizer = new ClaudeSummarizer(FakeCli.Failing(dir, 3, "boom"), TimeSpan.FromSeconds(60));

        var exception = await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeTranscriptAsync(Transcript, dir.Path));

        Assert.Contains("3", exception.Message, StringComparison.Ordinal);
        Assert.Contains("boom", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Timeout_KillsTheProcessTree()
    {
        using var dir = new TempDir();
        var summarizer = new ClaudeSummarizer(FakeCli.Hanging(dir), TimeSpan.FromSeconds(1));

        var exception = await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeTranscriptAsync(Transcript, dir.Path));

        Assert.Contains("終了しませんでした", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task MissingExecutable_Throws()
    {
        using var dir = new TempDir();
        var summarizer = new ClaudeSummarizer(dir.File("no-such-claude.exe"));

        await Assert.ThrowsAsync<SummarizeException>(
            () => summarizer.SummarizeTranscriptAsync(Transcript, dir.Path));
    }
}
