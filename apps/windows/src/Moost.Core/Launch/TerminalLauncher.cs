using System.Diagnostics;

namespace Moost.Core;

/// <summary>
/// 復帰コマンドを端末で実行する（conformance 詳細版 B の Windows 行・#103）。
///
/// <list type="bullet">
/// <item>Windows Terminal（<c>wt.exe</c>）があれば、新しいタブ/ウィンドウで PowerShell を起動する</item>
/// <item>無ければ <c>powershell.exe</c> を直接起動する（コンソールウィンドウが開く）</item>
/// <item>コマンド文字列は <see cref="ResumeCommand"/> が作ったもの（二重引用符を含まない）を渡す</item>
/// </list>
///
/// プロセスの起動は差し替え可能にしてある（テストでは実際に端末を開かない）。
/// </summary>
public sealed class TerminalLauncher
{
    private readonly Func<string, bool> _executableExists;
    private readonly Func<ProcessStartInfo, bool> _start;

    public TerminalLauncher(
        Func<string, bool>? executableExists = null,
        Func<ProcessStartInfo, bool>? start = null)
    {
        _executableExists = executableExists ?? DefaultExecutableExists;
        _start = start ?? DefaultStart;
    }

    /// <summary>Windows Terminal が使えるか（使えなければ PowerShell 単体にフォールバックする）。</summary>
    public bool UsesWindowsTerminal => _executableExists("wt.exe");

    /// <summary>
    /// 復帰コマンドを端末で実行する。起動に失敗したら <see cref="SummarizeException"/> ではなく
    /// <see cref="TerminalLaunchException"/> を投げる（UI はメッセージをそのまま表示する）。
    /// </summary>
    public void Launch(string command)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(command);

        var startInfo = BuildStartInfo(command, UsesWindowsTerminal);
        if (!_start(startInfo))
        {
            throw new TerminalLaunchException(
                $"{startInfo.FileName} を起動できませんでした。端末がインストールされているか確認してください。");
        }
    }

    /// <summary>
    /// 端末起動の引数を組み立てる（純粋・テスト可能）。
    ///
    /// <c>wt.exe</c> には「PowerShell を -NoExit で起動してコマンドを実行する」形で渡す。
    /// <c>-NoExit</c> により、復帰コマンドが終了してもウィンドウが閉じない（作業を続けられる）。
    /// </summary>
    public static ProcessStartInfo BuildStartInfo(string command, bool useWindowsTerminal)
    {
        ProcessStartInfo startInfo;

        if (useWindowsTerminal)
        {
            startInfo = new ProcessStartInfo("wt.exe")
            {
                UseShellExecute = false,
            };
            // wt は後続の引数を「起動するコマンドライン」として解釈する
            startInfo.ArgumentList.Add("powershell.exe");
            startInfo.ArgumentList.Add("-NoExit");
            startInfo.ArgumentList.Add("-Command");
            startInfo.ArgumentList.Add(command);
            return startInfo;
        }

        startInfo = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
        };
        startInfo.ArgumentList.Add("-NoExit");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(command);
        return startInfo;
    }

    private static bool DefaultExecutableExists(string fileName)
    {
        var path = AgentPathDetect.FromPath(fileName);
        return path is not null;
    }

    private static bool DefaultStart(ProcessStartInfo startInfo)
    {
        try
        {
            // 端末は独立プロセスとして開く（Moost の終了に巻き込まない）
            using var process = Process.Start(startInfo);
            return process is not null;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }
}

/// <summary>端末の起動に失敗した。</summary>
public sealed class TerminalLaunchException : Exception
{
    public TerminalLaunchException(string message)
        : base(message)
    {
    }
}
