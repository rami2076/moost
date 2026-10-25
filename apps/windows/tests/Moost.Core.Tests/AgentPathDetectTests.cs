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
    public void OverrideExpandsEnvironmentVariables()
    {
        using var dir = new TempDir();
        var expected = CreateFile(Path.Combine(dir.Path, "pi.exe"));

        var variable = "MOOST_TEST_BIN_" + Guid.NewGuid().ToString("N");
        Environment.SetEnvironmentVariable(variable, dir.Path);
        try
        {
            Assert.Equal(expected, AgentPathDetect.Pi($"%{variable}%\\pi.exe", dir.Path));
        }
        finally
        {
            Environment.SetEnvironmentVariable(variable, null);
        }
    }

    [Fact]
    public void FallsBackToWhereExe_ForCommandsOnPath()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // エージェント CLI の有無に依存しないよう、必ず存在するコマンドで PATH 解決を検証する
        // （CI ランナナーには claude が無いため、claude で検証すると環境依存になる）
        var detected = AgentPathDetect.FromPath("powershell");

        Assert.NotNull(detected);
        Assert.True(File.Exists(detected));
    }

    [Fact]
    public void FromPath_ReturnsNull_ForUnknownCommand()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.Null(AgentPathDetect.FromPath("moost-definitely-not-a-command"));
    }

    [Fact]
    public void AgentDetection_ReturnsNull_WhenNothingIsFound()
    {
        // どのプロファイルにも無く、PATH 上にも無いエージェントは null（未インストール扱い）
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
