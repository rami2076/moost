using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance A 章（JSON 永続基盤）。
/// </summary>
public class JsonFileStoreTests
{
    [Fact]
    public void A1_Write_LeavesNoTempFile_AndProducesValidJson()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        var store = new JsonFileStore(path);

        store.Write(new JsonObject { ["schemaVersion"] = 1, ["memos"] = new JsonArray() });

        Assert.True(File.Exists(path));
        Assert.False(File.Exists(path + JsonFileStore.TempSuffix), "一時ファイルが残ってはいけない");

        var text = File.ReadAllText(path);
        Assert.EndsWith("\n", text, StringComparison.Ordinal);
        Assert.NotNull(JsonNode.Parse(text));
    }

    [Fact]
    public void A1_Write_ReplacesPreviousContent()
    {
        using var dir = new TempDir();
        var path = dir.File("settings.json");
        var store = new JsonFileStore(path);

        store.Write(new JsonObject { ["schemaVersion"] = 1, ["terminalApp"] = "Terminal.app" });
        store.Write(new JsonObject { ["schemaVersion"] = 1, ["terminalApp"] = "WezTerm" });

        var loaded = store.Read();
        Assert.NotNull(loaded);
        Assert.Equal("WezTerm", loaded["terminalApp"]!.GetValue<string>());
    }

    [Fact]
    public void A2_CorruptJson_IsQuarantined_NotOverwritten()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        const string broken = "{ \"schemaVersion\": 1, \"memos\": [ ";
        File.WriteAllText(path, broken);
        var store = new JsonFileStore(path);

        var loaded = store.Read();

        Assert.Null(loaded);
        Assert.False(File.Exists(path)); // 壊れた本体は元の場所に残さない（退避する）

        var quarantined = Directory.GetFiles(dir.Path, "memos.json.corrupt-*");
        var name = Assert.Single(quarantined);
        Assert.Equal(broken, File.ReadAllText(name)); // 退避ファイルは元の内容を保持する（データを失わない）
        Assert.Matches(
            new Regex(@"\.corrupt-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d{3}Z$"),
            name);
    }

    [Fact]
    public void A2_NonObjectJson_IsQuarantined()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        File.WriteAllText(path, "[1,2,3]");
        var store = new JsonFileStore(path);

        Assert.Null(store.Read());
        Assert.False(File.Exists(path));
        Assert.Single(Directory.GetFiles(dir.Path, "memos.json.corrupt-*"));
    }

    [Fact]
    public void A2_MissingFile_ReturnsNull_WithoutQuarantine()
    {
        using var dir = new TempDir();
        var store = new JsonFileStore(dir.File("memos.json"));

        Assert.Null(store.Read());
        Assert.Empty(Directory.GetFiles(dir.Path));
    }

    [Fact]
    public void A3_ReadError_Propagates()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        File.WriteAllText(path, "{\"schemaVersion\":1}");
        var store = new JsonFileStore(path);

        // 他プロセスが排他ロックしている状況を作る。握りつぶして null にすると
        // 呼び出し側が「空のストア」として上書きし、既存データを失う（A3）。
        using var exclusive = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);

        Assert.ThrowsAny<IOException>(() => store.Read());
    }
}
