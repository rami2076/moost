using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance E6・E7（Codex の <c>history.jsonl</c> 集約）。
/// </summary>
public class CodexHistoryReaderTests
{
    private static CodexHistoryReader FixtureReader() => new(
        SpecPaths.TestData("codex_history.jsonl"),
        SummaryMarker.ConformanceMarker);

    [Fact]
    public void E6_AggregatesBySessionId_UsingLatestTs_AsSeconds()
    {
        var entries = FixtureReader().AggregatedEntries();

        var cs1 = Assert.Single(entries, entry => entry.SessionId == "CS1");
        Assert.Equal("second prompt", cs1.LastPrompt);
        // ts は epoch 秒 → 200 秒
        Assert.Equal(new DateTime(1970, 1, 1, 0, 3, 20, DateTimeKind.Utc), cs1.UpdatedAt);
    }

    [Fact]
    public void E6_OrdersNewestFirst()
    {
        var entries = FixtureReader().AggregatedEntries();

        Assert.Equal(["CS1", "CS2"], entries.Select(entry => entry.SessionId));
    }

    [Fact]
    public void E7_ExcludesForkOnlySessions_KeepingMixedOnes()
    {
        var entries = FixtureReader().AggregatedEntries();

        // CS3 はマーカー行のみなので消える
        Assert.DoesNotContain(entries, entry => entry.SessionId == "CS3");

        // CS2 はマーカー行だけ除外され、通常プロンプトが残る
        var cs2 = Assert.Single(entries, entry => entry.SessionId == "CS2");
        Assert.Equal("normal prompt", cs2.LastPrompt);
    }

    [Fact]
    public void MissingFile_YieldsNoEntries()
    {
        using var dir = new TempDir();
        var reader = new CodexHistoryReader(dir.File("history.jsonl"), SummaryMarker.Value);

        Assert.Empty(reader.AggregatedEntries());
    }
}
