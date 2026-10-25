using System.Diagnostics;
using System.Text;

namespace Moost.Core;

/// <summary>サブプロセス実行の結果。</summary>
internal sealed record ProcessOutcome(int ExitCode, string StdOut, string StdErr);

/// <summary>
/// 外部 CLI を安全に実行する小さなランナー（design.md 7 章のパイプ詰まり対策の Windows 版）。
///
/// <list type="bullet">
/// <item>stdout / stderr は<b>同時に</b>非同期で読み切る（片方を読まないとパイプが詰まってハングする）</item>
/// <item>タイムアウトでプロセスツリーごと kill する（CLI が固まっても UI を止めない）</item>
/// <item><c>.cmd</c> / <c>.bat</c>（npm 経由のシミング）は <c>cmd.exe /c</c> 経由で起動する</item>
/// <item>環境変数は呼び出し側が「消すもの」を null で渡せる（Claude Code の内部変数対策）</item>
/// </list>
/// </summary>
internal static class ProcessRunner
{
    public static async Task<ProcessOutcome> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory = null,
        string? stdinText = null,
        IReadOnlyDictionary<string, string?>? environment = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var startInfo = new ProcessStartInfo
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        // npm の .cmd シミングは Process.Start で直接起動できないため cmd.exe を挟む
        if (AgentPathDetect.RequiresCommandShell(executable))
        {
            startInfo.FileName = "cmd.exe";
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(executable);
        }
        else
        {
            startInfo.FileName = executable;
        }

        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        if (!string.IsNullOrEmpty(workingDirectory) && Directory.Exists(workingDirectory))
        {
            startInfo.WorkingDirectory = workingDirectory;
        }

        if (environment is not null)
        {
            foreach (var pair in environment)
            {
                // null を代入すると子プロセスの環境から取り除かれる
                startInfo.Environment[pair.Key] = pair.Value;
            }
        }

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                throw new SummarizeException($"{executable} を起動できませんでした。");
            }
        }
        catch (System.ComponentModel.Win32Exception exception)
        {
            throw new SummarizeException($"{executable} を起動できませんでした: {exception.Message}", exception);
        }

        // stdout / stderr は同時に読み切る（順番に読むとパイプバッファで詰まる）
        var stdoutTask = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
        var stderrTask = process.StandardError.ReadToEndAsync(CancellationToken.None);

        if (stdinText is not null)
        {
            try
            {
                await process.StandardInput.WriteAsync(stdinText).ConfigureAwait(false);
                await process.StandardInput.FlushAsync().ConfigureAwait(false);
            }
            catch (IOException)
            {
                // 子プロセスが stdin を読まずに終了した場合（broken pipe）は許容する
            }
        }

        try
        {
            process.StandardInput.Close();
        }
        catch (IOException)
        {
            // 既に閉じている場合は無視
        }

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        if (timeout is { } limit)
        {
            timeoutSource.CancelAfter(limit);
        }

        try
        {
            await process.WaitForExitAsync(timeoutSource.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            KillTree(process);
            throw new SummarizeException(
                $"{Path.GetFileName(executable)} が {timeout!.Value.TotalSeconds:0} 秒以内に終了しませんでした。");
        }
        catch (OperationCanceledException)
        {
            KillTree(process);
            throw;
        }

        var stdout = await stdoutTask.ConfigureAwait(false);
        var stderr = await stderrTask.ConfigureAwait(false);

        return new ProcessOutcome(process.ExitCode, stdout, stderr);
    }

    private static void KillTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
            }
        }
        catch (InvalidOperationException)
        {
            // 既に終了している
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // kill できない場合はあきらめる（タイムアウトの報告は行う）
        }
    }
}
