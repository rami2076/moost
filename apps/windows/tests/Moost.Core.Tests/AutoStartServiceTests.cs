using System.Runtime.Versioning;
using Microsoft.Win32;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// ログイン時の自動起動（#103）。OS の実状態を正とする（C4）。
///
/// テストは <c>HKCU\Software\MoostTests\&lt;guid&gt;</c> の使い捨てキーを使い、
/// 実アプリの登録（Run\Moost）には触らない。
/// </summary>
[SupportedOSPlatform("windows")]
public class AutoStartServiceTests
{
    private const string Root = @"Software\MoostTests";

    private static (AutoStartService Service, string KeyPath) Create()
    {
        var keyPath = Root + @"\" + Guid.NewGuid().ToString("N");
        return (new AutoStartService(keyPath, "MoostTest"), keyPath);
    }

    private static void Cleanup(string keyPath)
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(keyPath, throwOnMissingSubKey: false);
        }
        catch (Exception)
        {
            // 掃除の失敗はテスト結果に影響させない
        }
    }

    [Fact]
    public void IsDisabled_ByDefault()
    {
        var (service, keyPath) = Create();
        try
        {
            Assert.False(service.IsEnabled());
            Assert.Null(service.RegisteredCommand());
        }
        finally
        {
            Cleanup(keyPath);
        }
    }

    [Fact]
    public void Enable_RegistersQuotedPath()
    {
        var (service, keyPath) = Create();
        try
        {
            service.Enable(@"C:\Program Files\Moost\Moost.exe");

            Assert.True(service.IsEnabled());
            // スペース入りパスでも壊れないよう引用符で囲む
            Assert.Equal("\"C:\\Program Files\\Moost\\Moost.exe\"", service.RegisteredCommand());
        }
        finally
        {
            Cleanup(keyPath);
        }
    }

    [Fact]
    public void Disable_RemovesTheValue_AndIsIdempotent()
    {
        var (service, keyPath) = Create();
        try
        {
            service.Enable(@"C:\Moost\Moost.exe");
            service.Disable();

            Assert.False(service.IsEnabled());

            // 未登録の状態で呼んでも例外にしない
            service.Disable();
            Assert.False(service.IsEnabled());
        }
        finally
        {
            Cleanup(keyPath);
        }
    }

    [Fact]
    public void Enable_RejectsEmptyPath()
    {
        var (service, keyPath) = Create();
        try
        {
            Assert.Throws<ArgumentException>(() => service.Enable("  "));
        }
        finally
        {
            Cleanup(keyPath);
        }
    }

    [Fact]
    public void DefaultKeyPath_IsTheCurrentUserRunKey()
    {
        // 実アプリが使う場所の確認（登録はしない）
        var service = new AutoStartService();
        Assert.Equal(@"Software\Microsoft\Windows\CurrentVersion\Run", AutoStartService.DefaultKeyPath);
        Assert.Equal("Moost", AutoStartService.DefaultValueName);
        // 呼んでも例外にならないこと（読み取りのみ）
        _ = service.IsEnabled();
    }
}
