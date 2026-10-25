using System.Diagnostics;

namespace Moost.Core;

/// <summary>
/// claude / codex / pi / hermes コマンドの検出（design.md 7 章【1】GUI の PATH 問題の Windows 版）。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/AgentPathDetect.swift</c>。
///
/// 順序: 設定の手動上書き → 既知パス → <c>where.exe</c>。
/// GUI から起動すると PATH が最小限になり bare なコマンドが解決できないため、この 3 段構えにする。
/// 上書きが指定された場合は検出結果より優先し、実在しなければ null を返す（リファレンス実装と同じ）。
/// </summary>
public static class AgentPathDetect
{
    /// <summary>検出したコマンドの実行に cmd.exe を挟む必要があるか（<c>.cmd</c> / <c>.bat</c>）。</summary>
    public static bool RequiresCommandShell(string? filePath) =>
        filePath is not null
        && (filePath.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
            || filePath.EndsWith(".bat", StringComparison.OrdinalIgnoreCase));

    public static string? Claude(string overridePath = "", string? userProfile = null) =>
        Detect(overridePath, "claude", KnownPaths("claude", userProfile));

    public static string? Codex(string overridePath = "", string? userProfile = null) =>
        Detect(overridePath, "codex", KnownPaths("codex", userProfile));

    public static string? Pi(string overridePath = "", string? userProfile = null) =>
        Detect(overridePath, "pi", KnownPaths("pi", userProfile));

    public static string? Hermes(string overridePath = "", string? userProfile = null) =>
        Detect(overridePath, "hermes", KnownPaths("hermes", userProfile));

    /// <summary>
    /// Windows の既知パス。ネイティブインストーラは <c>%USERPROFILE%\.local\bin</c>、
    /// npm グローバルは <c>%APPDATA%\npm</c> に <c>.cmd</c> のシミングを置く。
    /// </summary>
    private static IEnumerable<string> KnownPaths(string command, string? userProfile)
    {
        var home = userProfile ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appData = userProfile is null
            ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
            : Path.Combine(home, "AppData", "Roaming");

        return
        [
            Path.Combine(home, ".local", "bin", command + ".exe"),
            Path.Combine(appData, "npm", command + ".cmd"),
            Path.Combine(home, ".local", "bin", command),
        ];
    }

    private static string? Detect(string overridePath, string command, IEnumerable<string> knownPaths)
    {
        if (!string.IsNullOrEmpty(overridePath))
        {
            // 上書き指定は検出結果より優先する。実在しなければ「なし」
            var expanded = Expand(overridePath);
            return File.Exists(expanded) ? expanded : null;
        }

        foreach (var path in knownPaths)
        {
            if (File.Exists(path))
            {
                return path;
            }
        }

        return WhereViaWhereExe(command);
    }

    /// <summary><c>where.exe</c> で PATH から解決する（GUI 起動で PATH が最小限な場合の最後の手段）。</summary>
    private static string? WhereViaWhereExe(string command)
    {
        try
        {
            var startInfo = new ProcessStartInfo("where.exe")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            startInfo.ArgumentList.Add(command);

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return null;
            }

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                return null;
            }

            // where は複数行を返しうる。最初の行（PATH 順で最優先）を採用する
            foreach (var line in output.Split('\n'))
            {
                var trimmed = line.Trim();
                if (trimmed.Length > 0)
                {
                    return trimmed;
                }
            }

            return null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    /// <summary>上書きパスの展開。<c>~</c> と <c>%VAR%</c> を許す。</summary>
    private static string Expand(string path)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var expanded = path;
        if (expanded == "~")
        {
            expanded = home;
        }
        else if (expanded.StartsWith("~/", StringComparison.Ordinal) || expanded.StartsWith("~\\", StringComparison.Ordinal))
        {
            expanded = Path.Combine(home, expanded[2..]);
        }

        return Environment.ExpandEnvironmentVariables(expanded);
    }
}
