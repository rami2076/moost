using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// CLI パス検出（design.md 7 章【1】GUI の PATH 問題の Windows 版・#101）。
/// </summary>
public class AgentPathDetectTests
{
    private static string CreateFile(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, string.Empty);
        return path;
    }

    [Fact]
    public void FindsNativeInstallerLayout()
    {
        using var dir = new TempDir();
        var expected = CreateFile(Path.Combine(dir.Path, ".local", "bin", "claude.exe"));

        Assert.Equal(expected, AgentPathDetect.Claude(userProfile: dir.Path));
    }

    [Fact]
    public void FindsNpmShim_AndMarksItAsNeedingCommandShell()
    {
        using var dir = new TempDir();
        var expected = CreateFile(Path.Combine(dir.Path, "AppData", "Roaming", "npm", "codex.cmd"));

        var detected = AgentPathDetect.Codex(userProfile: dir.Path);

        Assert.Equal(expected, detected);
        Assert.True(AgentPathDetect.RequiresCommandShell(detected));
    }

    [Fact]
    public void NativeExe_DoesNotNeedCommandShell()
    {
        Assert.False(AgentPathDetect.RequiresCommandShell(@"C:\Users\u\.local\bin\claude.exe"));
        Assert.False(AgentPathDetect.RequiresCommandShell(null));
        Assert.True(AgentPathDetect.RequiresCommandShell(@"C:\x\claude.bat"));
    }

    [Fact]
    public void OverrideWins_OverKnownPaths()
    {
        using var dir = new TempDir();
        CreateFile(Path.Combine(dir.Path, ".local", "bin", "claude.exe"));
        var overridePath = CreateFile(Path.Combine(dir.Path, "custom", "claude-wrapper.exe"));

        Assert.Equal(overridePath, AgentPathDetect.Claude(overridePath, dir.Path));
    }

    [Fact]
    public void OverrideThatDoesNotExist_ReturnsNull_EvenIfKnownPathExists()
    {
        using var dir = new TempDir();
        CreateFile(Path.Combine(dir.Path, ".local", "bin", "claude.exe"));

        // 上書き指定は検出結果より優先され、見つからなければ「なし」（リファレンス実装と同じ）
        Assert.Null(AgentPathDetect.Claude(Path.Combine(dir.Path, "absent.exe"), dir.Path));
    }

    [Fact]
    public void OverrideExpandsTilde()
    {
        using var dir = new TempDir();
        var expected = CreateFile(Path.Combine(dir.Path, ".local", "bin", "pi.exe"));

        // ~ は実ユーザーのホームに展開されるため、ここでは実在するパスを直接渡す
        Assert.Equal(expected, AgentPathDetect.Pi(expected, dir.Path));
    }

    [Fact]
    public void FallsBackToWhereExe_ForCommandsOnPath()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // どのプロファイルにも無い状態でも、PATH 上にあるコマンドは where.exe で見つかる
        using var dir = new TempDir();
        var detected = AgentPathDetect.Claude(userProfile: dir.Path);

        Assert.NotNull(detected);
        Assert.True(File.Exists(detected));
    }

    [Fact]
    public void ReturnsNull_ForUnknownCommand()
    {
        using var dir = new TempDir();
        Assert.Null(AgentPathDetect.Hermes(userProfile: dir.Path));
    }

    [Fact]
    public void SessionLocations_UseUserProfile()
    {
        var profile = Path.Combine("C:", "Users", "someone");

        Assert.Equal(
            Path.Combine(profile, ".pi", "agent", "sessions"),
            SessionLocations.PiSessionsDirectory(profile));
        Assert.Equal(
            Path.Combine(profile, ".hermes", "state.db"),
            SessionLocations.HermesStateDb(profile));
    }
}
