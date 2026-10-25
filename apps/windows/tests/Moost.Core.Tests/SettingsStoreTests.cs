using System.Text.Json.Nodes;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance C 章（settings.json）。読み込みは寛容で、型が違う項目だけデフォルトへ戻す。
/// </summary>
public class SettingsStoreTests
{
    [Fact]
    public void C1_BadTypesFixture_FallsBackPerField()
    {
        using var dir = new TempDir();
        var store = new SettingsStore(dir.CopyFixture("settings_bad_types.json"));

        var settings = store.Load();

        Assert.Equal("Terminal.app", settings.TerminalApp);
        Assert.Equal(20, settings.RecentSessionLimit);
        Assert.Equal("", settings.ClaudePath);
        Assert.Equal(1, settings.SummaryRallyCount);
        Assert.True(settings.CopyAnimation);
    }

    [Fact]
    public void C1_GoodFieldsAreKept_WhileBadOnesFallBack()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        File.WriteAllText(path, """
            {
              "schemaVersion": 1,
              "terminalApp": "WezTerm",
              "recentSessionLimit": "many",
              "claudePath": "C:\\tools\\claude.exe",
              "summaryRallyCount": 7,
              "copyAnimation": "yes"
            }
            """);

        var settings = new SettingsStore(path).Load();

        Assert.Equal("WezTerm", settings.TerminalApp);          // 型が正しいので保持
        Assert.Equal("C:\\tools\\claude.exe", settings.ClaudePath);
        Assert.Equal(7, settings.SummaryRallyCount);
        Assert.Equal(20, settings.RecentSessionLimit);           // 型違い → その項目だけ既定値
        Assert.True(settings.CopyAnimation);                     // 型違い → その項目だけ既定値
    }

    [Fact]
    public void C2_MissingFile_ReturnsDefaults()
    {
        using var dir = new TempDir();
        var settings = new SettingsStore(dir.File("settings.json")).Load();

        Assert.Equal(Settings.Default, settings);
    }

    [Fact]
    public void C2_CorruptFile_ReturnsDefaults_AndQuarantines()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        File.WriteAllText(path, "{ broken");
        var settings = new SettingsStore(path).Load();

        Assert.Equal(Settings.Default, settings);
        Assert.Single(Directory.GetFiles(dir.Path, "settings.json.corrupt-*"));
    }

    [Theory]
    [InlineData("WezTerm")]
    [InlineData("wt.exe")]
    [InlineData("iTerm2")]
    [InlineData("kitty")]
    [InlineData("未知のターミナル")]
    public void C3_TerminalApp_IsNotEnumified(string app)
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        File.WriteAllText(path, $$"""{ "schemaVersion": 1, "terminalApp": "{{app}}" }""");

        Assert.Equal(app, new SettingsStore(path).Load().TerminalApp);
    }

    [Fact]
    public void C4_Save_DoesNotPersistLoginItem()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        new SettingsStore(path).Save(Settings.Default with { TerminalApp = "wt.exe" });

        var json = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var keys = json.Select(pair => pair.Key).ToArray();

        // OS の実状態を正とするため、自動起動の類は保存しない（C4）
        Assert.DoesNotContain("loginItem", keys);
        Assert.DoesNotContain("launchAtLogin", keys);
        Assert.DoesNotContain("startAtLogin", keys);
        Assert.DoesNotContain("autoStart", keys);
        Assert.Equal(1, json["schemaVersion"]!.GetValue<int>());
    }

    [Fact]
    public void SaveLoad_RoundTrips()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        var store = new SettingsStore(path);

        var original = new Settings
        {
            TerminalApp = "wt.exe",
            RecentSessionLimit = 42,
            ClaudePath = "C:\\bin\\claude.exe",
            SummaryRallyCount = 5,
            CopyAnimation = false,
            PiProvider = "local",
            PiModel = "qwen3",
        };
        store.Save(original);

        Assert.Equal(original, store.Load());
    }

    [Fact]
    public void PiFields_DefaultToEmpty_AndAreRead()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        File.WriteAllText(path, """
            { "schemaVersion": 1, "piProvider": "dspark", "piModel": 123 }
            """);

        var settings = new SettingsStore(path).Load();

        Assert.Equal("dspark", settings.PiProvider);
        Assert.Equal("", settings.PiModel); // 型違いは既定値
    }
}
