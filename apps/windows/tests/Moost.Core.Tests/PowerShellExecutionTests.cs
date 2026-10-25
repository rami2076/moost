using System.Diagnostics;
using System.Text;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance G1 の実行レベル検証。
///
/// 文字列の見た目ではなく、<b>実際に PowerShell で実行して注入が作動しないこと</b>を確かめる。
/// パスに <c>'</c> <c>;</c> <c>$</c> バッククォート <c>&amp;</c> を含めても 1 つのリテラルとして扱われ、
/// 2 文目が勝手に実行されないことを検証する。
///
/// 注: Windows のファイル名に使えない文字（<c>|</c> <c>&gt;</c> <c>&lt;</c> <c>"</c> <c>*</c> <c>?</c>）は
/// パスの実体を作れないため、それらは文字列レベルのテスト（<see cref="PowerShellQuoteTests"/>）で扱う。
/// </summary>
public class PowerShellExecutionTests
{
    private static bool CanRun => OperatingSystem.IsWindows();

    private static (int ExitCode, string StdOut, string StdErr) RunPowerShell(
        string script,
        IReadOnlyDictionary<string, string?>? environment = null)
    {
        var startInfo = new ProcessStartInfo("powershell.exe")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(script);

        if (environment is not null)
        {
            foreach (var pair in environment)
            {
                startInfo.Environment[pair.Key] = pair.Value;
            }
        }

        using var process = Process.Start(startInfo)!;
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        process.WaitForExit();

        return (process.ExitCode, stdout.Result.Trim(), stderr.Result.Trim());
    }

    [Fact]
    public void SetLocation_HandlesSpacesDollarBacktickSemicolonAmpersandAndQuotes()
    {
        if (!CanRun)
        {
            return;
        }

        using var dir = new TempDir();
        // Windows のファイル名として有効な「危険文字」を全部入れる
        var target = Path.Combine(dir.Path, "we ird$`;&'(x)[1]#%+,=");
        Directory.CreateDirectory(target);

        var (exitCode, stdout, stderr) = RunPowerShell(
            ResumeCommand.SetLocation(target) + "Write-Output ((Get-Location).Path)");

        Assert.Equal(0, exitCode);
        Assert.Equal("", stderr);
        Assert.Equal(target, stdout, ignoreCase: true);
    }

    [Fact]
    public void SetLocation_DoesNotExpandWildcards()
    {
        if (!CanRun)
        {
            return;
        }

        using var dir = new TempDir();
        var bracketed = Path.Combine(dir.Path, "a[1]");
        var plain = Path.Combine(dir.Path, "a1");
        Directory.CreateDirectory(bracketed);
        Directory.CreateDirectory(plain);

        var (_, stdout, _) = RunPowerShell(
            ResumeCommand.SetLocation(bracketed) + "Write-Output ((Get-Location).Path)");

        // -Path（= cd の既定）だと a1 にマッチしてしまう。-LiteralPath なので a[1] のまま
        Assert.Equal(bracketed, stdout, ignoreCase: true);
    }

    [Fact]
    public void InjectedStatementsInProjectPath_DoNotExecute()
    {
        if (!CanRun)
        {
            return;
        }

        // 実在しないパスに「閉じ引用符 + 追加コマンド」を仕込む（注入の典型）
        const string evil = @"C:\no-such-dir\'; Write-Output INJECTED; '";
        var (_, stdout, _) = RunPowerShell(
            ResumeCommand.SetLocation(evil) + "Write-Output 'MARK'");

        // Set-Location は失敗するが、注入された Write-Output は実行されない
        Assert.Equal("MARK", stdout);
        Assert.DoesNotContain("INJECTED", stdout);
    }

    [Fact]
    public void UnsetPrefix_RemovesClaudeInternalEnvVars_ButKeepsOthers()
    {
        if (!CanRun)
        {
            return;
        }

        var script = ClaudeEnvironment.UnsetPrefix()
            + "Write-Output ('A=' + $env:CLAUDE_CODE_CHILD_SESSION"
            + " + '|B=' + $env:CLAUDECODE"
            + " + '|C=' + $env:AI_AGENT"
            + " + '|D=' + $env:OTHER)";

        var (exitCode, stdout, _) = RunPowerShell(script, new Dictionary<string, string?>
        {
            ["CLAUDE_CODE_CHILD_SESSION"] = "1",
            ["CLAUDECODE"] = "1",
            ["AI_AGENT"] = "1",
            ["OTHER"] = "keep",
        });

        Assert.Equal(0, exitCode);
        Assert.Equal("A=|B=|C=|D=keep", stdout);
    }

    [Fact]
    public void ResumeCommand_Semicolon_KeepsRunningAfterFailedSetLocation()
    {
        if (!CanRun)
        {
            return;
        }

        // `;` は `&&` と違い前段の失敗で止めない（復帰コマンドとしては、
        // 端末が開いたこと自体を優先する）。挙動を明示的に固定しておく。
        var (_, stdout, _) = RunPowerShell(
            ResumeCommand.SetLocation(@"C:\no-such-dir") + "Write-Output 'MARK'");

        Assert.Equal("MARK", stdout);
    }
}
