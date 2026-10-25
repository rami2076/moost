using System.Text;

namespace Moost.Core.Tests;

/// <summary>
/// テスト用の偽 CLI（<c>.cmd</c> + <c>.ps1</c>）。
///
/// <c>.cmd</c> を挟むことで、実際の Windows の npm シミング経路
/// （<c>cmd.exe /c</c> 経由の起動）をそのまま検証できる。
///
/// 注意: Windows PowerShell 5.1 の stdout は OEM コードページで書かれるため、
/// 日本語を含む引数を stdout で観測すると化ける（実 CLI は Node 製で UTF-8 を書くので実害はない）。
/// テストでは引数・stdin を <b>UTF-8 のファイル</b>に書かせて観測する。
/// </summary>
internal static class FakeCli
{
    private static string WriteScript(string directory, string name, string content, bool crlf = false)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, name);
        var text = crlf ? content.Replace("\n", "\r\n", StringComparison.Ordinal) : content;
        File.WriteAllText(path, text, new UTF8Encoding(false));
        return path;
    }

    /// <summary>引数と stdin・環境変数を観測できる claude の偽物（stdout は ASCII のみ）。</summary>
    public static string ClaudeEcho(TempDir dir)
    {
        WriteScript(dir.Path, "fake-claude.ps1", """
            $stdin = [Console]::In.ReadToEnd()
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'stdin.txt'), $stdin, $utf8)
            [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'args.txt'), ($args -join '|'), $utf8)
            Write-Output ('ENV=' + $env:CLAUDE_CODE_CHILD_SESSION)
            """);
        return WriteScript(dir.Path, "fake-claude.cmd", """
            @echo off
            powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-claude.ps1" %*
            """, crlf: true);
    }

    /// <summary>
    /// 受け取った引数を <c>--output-last-message</c> のファイル（UTF-8）に書き出す codex の偽物。
    /// stdout には進捗ログ相当の ASCII を出す。
    /// </summary>
    public static string CodexEchoArgs(TempDir dir)
    {
        WriteScript(dir.Path, "fake-codex.ps1", """
            $out = $null
            for ($i = 0; $i -lt $args.Count - 1; $i++) {
              if ($args[$i] -eq '--output-last-message') { $out = $args[$i + 1] }
            }
            if ($out) {
              $utf8 = New-Object System.Text.UTF8Encoding($false)
              [System.IO.File]::WriteAllText($out, ('ARGS=' + ($args -join '|')), $utf8)
            }
            Write-Output 'progress log line'
            """);
        return WriteScript(dir.Path, "fake-codex.cmd", """
            @echo off
            powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-codex.ps1" %*
            """, crlf: true);
    }

    /// <summary>指定の終了コードと stderr を返す偽物。</summary>
    public static string Failing(TempDir dir, int exitCode, string stderr) =>
        WriteScript(dir.Path, "fake-fail.cmd", $"""
            @echo off
            echo {stderr} 1>&2
            exit /b {exitCode}
            """, crlf: true);

    /// <summary>終了しない偽物（タイムアウト検証用）。</summary>
    public static string Hanging(TempDir dir) =>
        WriteScript(dir.Path, "fake-hang.cmd", """
            @echo off
            ping -n 30 127.0.0.1 > nul
            """, crlf: true);
}
