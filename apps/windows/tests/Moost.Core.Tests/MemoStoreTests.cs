using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance B 章（memos.json）。Fixture は <c>spec/testdata/</c> をそのまま使う。
/// </summary>
public class MemoStoreTests
{
    private static Memo NewMemo(string id = "m-1", string sessionId = "S-1") => new()
    {
        Id = id,
        Agent = "claude-code",
        SessionId = sessionId,
        Title = "title",
        Tags = ["a"],
        Body = "body",
        ProjectPath = "/work/proj",
        CreatedAt = new DateTime(2026, 9, 20, 9, 0, 0, DateTimeKind.Utc),
        UpdatedAt = new DateTime(2026, 9, 20, 9, 0, 0, DateTimeKind.Utc),
    };

    [Fact]
    public void B1_Envelope_HasSchemaVersionAndMemos()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        new MemoStore(path).Add(NewMemo());

        var json = JsonNode.Parse(File.ReadAllText(path))!.AsObject();

        Assert.Equal(1, json["schemaVersion"]!.GetValue<int>());
        var memos = json["memos"]!.AsArray();
        Assert.Single(memos);
        Assert.Equal("m-1", memos[0]!["id"]!.GetValue<string>());
    }

    [Fact]
    public void B2_ValidFixture_ReadsBothMemos_KeepingDangerousCharacters()
    {
        using var dir = new TempDir();
        var store = new MemoStore(dir.CopyFixture("memos_valid.json"));

        var memos = store.Load();

        Assert.Equal(2, memos.Count);
        Assert.Equal("認証リファクタの途中状態", memos[0].Title);
        Assert.Equal(["auth", "wip"], memos[0].Tags);

        // 危険文字はそのままの値で保持される（エスケープ解除・改変をしない）
        Assert.Equal("危険文字を含む表題 `echo $(whoami)` | tee x", memos[1].Title);
        Assert.Equal(["backtick `x`", "pipe|"], memos[1].Tags);
        Assert.Contains("$VAR", memos[1].Body, StringComparison.Ordinal);
        Assert.Contains(">/dev/null", memos[1].Body, StringComparison.Ordinal);
    }

    [Fact]
    public void B3_CorruptEntry_IsSkipped_StoreIsNotDiscarded()
    {
        using var dir = new TempDir();
        var store = new MemoStore(dir.CopyFixture("memos_corrupt_entry.json"));

        var memos = store.Load();

        var memo = Assert.Single(memos);
        Assert.Equal("S-OK", memo.SessionId);
        Assert.Equal("健全な 1 件", memo.Title);
    }

    [Fact]
    public void B4_Update_ChangesOnlyMutableFields()
    {
        using var dir = new TempDir();
        var store = new MemoStore(dir.CopyFixture("memos_valid.json"));
        var before = store.Load()[0];

        var updatedAt = new DateTime(2026, 10, 25, 12, 0, 0, DateTimeKind.Utc);
        var ok = store.Update(
            before.Id,
            title: "新しい表題",
            tags: ["x", "y"],
            body: "新しい本文",
            updatedAt: updatedAt);

        Assert.True(ok);
        var after = store.Load()[0];

        // 可変フィールドだけが変わる
        Assert.Equal("新しい表題", after.Title);
        Assert.Equal(["x", "y"], after.Tags);
        Assert.Equal("新しい本文", after.Body);
        Assert.Equal(updatedAt, after.UpdatedAt);

        // 不変フィールドは動かない（ADR-003）
        Assert.Equal(before.Id, after.Id);
        Assert.Equal(before.Agent, after.Agent);
        Assert.Equal(before.SessionId, after.SessionId);
        Assert.Equal(before.ProjectPath, after.ProjectPath);
        Assert.Equal(before.CreatedAt, after.CreatedAt);
    }

    [Fact]
    public void B4_UpdateAndDelete_ReturnFalse_WhenIdIsUnknown()
    {
        using var dir = new TempDir();
        var store = new MemoStore(dir.CopyFixture("memos_valid.json"));

        Assert.False(store.Update("no-such-id", title: "x"));
        Assert.False(store.Delete("no-such-id"));
    }

    [Fact]
    public void B4_Delete_RemovesOnlyTargetMemo()
    {
        using var dir = new TempDir();
        var store = new MemoStore(dir.CopyFixture("memos_valid.json"));
        var target = store.Load()[1];

        Assert.True(store.Delete(target.Id));

        var memo = Assert.Single(store.Load());
        Assert.NotEqual(target.Id, memo.Id);
    }

    [Theory]
    [InlineData("a, b ,,c", new[] { "a", "b", "c" })]
    [InlineData("", new string[0])]
    [InlineData(" , ", new string[0])]
    [InlineData("solo", new[] { "solo" })]
    [InlineData("dup,,dup", new[] { "dup", "dup" })]
    public void B5_ParseTags_SplitsTrimsAndDropsEmpty(string input, string[] expected)
    {
        Assert.Equal(expected, Memo.ParseTags(input));
    }

    [Fact]
    public void B6_WritesUtcIso8601_WithMilliseconds()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        new MemoStore(path).Add(NewMemo());

        var text = File.ReadAllText(path);

        Assert.Matches(new Regex("\"createdAt\": \"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z\""), text);
        Assert.Matches(new Regex("\"updatedAt\": \"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z\""), text);
    }

    [Theory]
    [InlineData("2026-09-20T09:00:00Z")]
    [InlineData("2026-09-20T09:00:00.000Z")]
    [InlineData("2026-09-20T18:00:00+09:00")]
    public void B6_ReadsTolerantly(string text)
    {
        Assert.True(IsoUtc.TryParse(text, out var parsed));
        Assert.Equal(new DateTime(2026, 9, 20, 9, 0, 0, DateTimeKind.Utc), parsed);
        Assert.Equal(DateTimeKind.Utc, parsed.Kind);
    }

    [Fact]
    public void B6_RejectsUnparsableDates()
    {
        Assert.False(IsoUtc.TryParse("not-a-date", out _));
        Assert.False(IsoUtc.TryParse("", out _));
    }

    [Fact]
    public void B2_Load_OnMissingFile_ReturnsEmpty()
    {
        using var dir = new TempDir();
        Assert.Empty(new MemoStore(dir.File("memos.json")).Load());
    }

    [Fact]
    public void B3_MemoWithNumericBody_IsRejected()
    {
        using var dir = new TempDir();
        var path = dir.File("memos.json");
        File.WriteAllText(path, """
            {
              "schemaVersion": 1,
              "memos": [
                { "id": "x", "agent": "claude-code", "sessionId": "S", "title": "t",
                  "tags": [], "body": 42, "projectPath": "/p",
                  "createdAt": "2026-09-01T00:00:00.000Z", "updatedAt": "2026-09-01T00:00:00.000Z" }
              ]
            }
            """);

        Assert.Empty(new MemoStore(path).Load());
    }
}
