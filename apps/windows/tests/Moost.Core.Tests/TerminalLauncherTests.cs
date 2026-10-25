using System.Diagnostics;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 端末起動（#103）。実際に端末は開かず、組み立てた引数とフォールバックを検証する。
/// </summary>
public class TerminalLauncherTests
{
    private const string Command = "Set-Location -LiteralPath 'C:\\work\\alpha'; claude --resume 's-1'";

    [Fact]
    public void UsesWindowsTerminal_WhenWtExists()
    {
        var launcher = new TerminalLauncher(
            executableExists: name => name == "wt.exe",
            start: _ => true);

        Assert.True(launcher.UsesWindowsTerminal);
    }

    [Fact]
    public void BuildStartInfo_PrefersWindowsTerminal()
    {
        var startInfo = TerminalLauncher.BuildStartInfo(Command, useWindowsTerminal: true);

        Assert.Equal("wt.exe", startInfo.FileName);
        Assert.Equal(
            ["powershell.exe", "-NoExit", "-Command", Command],
            startInfo.ArgumentList.ToArray());
    }

    [Fact]
    public void BuildStartInfo_FallsBackToPowerShell()
    {
        var startInfo = TerminalLauncher.BuildStartInfo(Command, useWindowsTerminal: false);

        Assert.Equal("powershell.exe", startInfo.FileName);
        Assert.Equal(["-NoExit", "-Command", Command], startInfo.ArgumentList.ToArray());
    }

    [Fact]
    public void BuildStartInfo_DoesNotUseShellExecute()
    {
        // UseShellExecute=true だと引数の受け渡しが OS 任せになり、引用の扱いが変わる
        Assert.False(TerminalLauncher.BuildStartInfo(Command, useWindowsTerminal: true).UseShellExecute);
        Assert.False(TerminalLauncher.BuildStartInfo(Command, useWindowsTerminal: false).UseShellExecute);
    }

    [Fact]
    public void Launch_StartsTheTerminalWithTheResumeCommand()
    {
        ProcessStartInfo? captured = null;
        var launcher = new TerminalLauncher(
            executableExists: name => name == "wt.exe",
            start: startInfo =>
            {
                captured = startInfo;
                return true;
            });

        launcher.Launch(Command);

        Assert.NotNull(captured);
        Assert.Equal("wt.exe", captured!.FileName);
        Assert.Contains(Command, captured.ArgumentList);
    }

    [Fact]
    public void Launch_Throws_WhenTheTerminalCannotStart()
    {
        var launcher = new TerminalLauncher(
            executableExists: _ => false,
            start: _ => false);

        var exception = Assert.Throws<TerminalLaunchException>(() => launcher.Launch(Command));
        Assert.Contains("powershell.exe", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Launch_RejectsEmptyCommand()
    {
        var launcher = new TerminalLauncher(executableExists: _ => false, start: _ => true);

        Assert.Throws<ArgumentException>(() => launcher.Launch("   "));
    }

    [Fact]
    public void Launch_UsesPowerShell_WhenWindowsTerminalIsMissing()
    {
        ProcessStartInfo? captured = null;
        var launcher = new TerminalLauncher(
            executableExists: _ => false,
            start: startInfo =>
            {
                captured = startInfo;
                return true;
            });

        launcher.Launch(Command);

        Assert.Equal("powershell.exe", captured!.FileName);
    }
}
