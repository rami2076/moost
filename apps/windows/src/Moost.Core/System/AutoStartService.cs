using System.Runtime.Versioning;
using Microsoft.Win32;

namespace Moost.Core;

/// <summary>
/// ログイン時の自動起動（design.md 6 章・C4）。
///
/// **OS の実状態を正**とし、設定ファイルには保存しない（C4）。
/// Windows では <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c> の値を読み書きする
/// （管理者権限は不要）。
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class AutoStartService
{
    /// <summary>既定のレジストリキー（現在ユーザー）。</summary>
    public const string DefaultKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>既定の値名。</summary>
    public const string DefaultValueName = "Moost";

    private readonly string _keyPath;
    private readonly string _valueName;

    public AutoStartService(string? keyPath = null, string? valueName = null)
    {
        _keyPath = keyPath ?? DefaultKeyPath;
        _valueName = valueName ?? DefaultValueName;
    }

    /// <summary>
    /// 自動起動が登録されているか（OS の実状態を毎回読む）。
    /// </summary>
    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(_keyPath, writable: false);
        return key?.GetValue(_valueName) is string value && value.Length > 0;
    }

    /// <summary>登録されているコマンドライン（未登録なら null）。</summary>
    public string? RegisteredCommand()
    {
        using var key = Registry.CurrentUser.OpenSubKey(_keyPath, writable: false);
        return key?.GetValue(_valueName) as string;
    }

    /// <summary>
    /// 自動起動を有効にする。<paramref name="executablePath"/> は引用符で囲んで登録する
    /// （パスにスペースがあっても壊れないように）。
    /// </summary>
    public void Enable(string executablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);

        using var key = Registry.CurrentUser.CreateSubKey(_keyPath, writable: true)
            ?? throw new InvalidOperationException($"レジストリキーを開けません: HKCU\\{_keyPath}");
        key.SetValue(_valueName, "\"" + executablePath + "\"", RegistryValueKind.String);
    }

    /// <summary>自動起動を解除する（未登録でもエラーにしない）。</summary>
    public void Disable()
    {
        using var key = Registry.CurrentUser.OpenSubKey(_keyPath, writable: true);
        key?.DeleteValue(_valueName, throwOnMissingValue: false);
    }
}
