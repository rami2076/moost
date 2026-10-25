using System.Text.RegularExpressions;

namespace Moost.Core.Tests;

/// <summary>
/// スキャフォールドの配線確認: <c>spec/</c> の Fixture がテストから到達でき、
/// conformance の全項目が読み取れることを検証する。
///
/// 個々の項目（A1〜H）を緑にするのは #98 以降。ここでは「同じ Fixture を使う土台がある」ことだけを固定する。
/// </summary>
public class SpecWiringTests
{
    /// <summary>conformance の項目数。spec 側を意図的に変更したときだけ、この値を更新する。</summary>
    private const int ExpectedConformanceItems = 26;

    private static readonly Regex ItemLine = new(@"^\| ([A-H][0-9]+) \|", RegexOptions.Multiline);

    [Fact]
    public void ConformanceExists()
    {
        Assert.True(File.Exists(SpecPaths.Conformance), $"conformance.md がありません: {SpecPaths.Conformance}");
    }

    [Fact]
    public void ConformanceHasAllItems()
    {
        var text = File.ReadAllText(SpecPaths.Conformance);
        var ids = ItemLine.Matches(text).Select(m => m.Groups[1].Value).ToHashSet();

        Assert.Equal(ExpectedConformanceItems, ids.Count);

        // 章ごとの代表項目が存在すること（A〜G が揃っていることの確認）
        foreach (var id in new[] { "A1", "B1", "C1", "D1", "E1", "F1", "G1" })
        {
            Assert.Contains(id, ids);
        }
    }

    [Fact]
    public void SharedFixturesAreReachable()
    {
        Assert.True(File.Exists(SpecPaths.TestData("history.jsonl")));
        Assert.True(File.Exists(SpecPaths.TestData("codex_history.jsonl")));
        Assert.True(File.Exists(SpecPaths.TestData("memos_valid.json")));
        Assert.True(File.Exists(SpecPaths.TestData("settings_bad_types.json")));
    }

    [Fact]
    public void SchemasAreReachable()
    {
        Assert.True(File.Exists(SpecPaths.Schema("memos.schema.json")));
        Assert.True(File.Exists(SpecPaths.Schema("settings.schema.json")));
        Assert.True(File.Exists(SpecPaths.Schema("projects.schema.json")));
    }

    [Fact]
    public void FixturesUseLfLineEndings()
    {
        // CRLF でチェックアウトされると JSONL のパーステストが落ちる（.gitattributes で LF 固定）
        var text = File.ReadAllText(SpecPaths.TestData("history.jsonl"));
        Assert.DoesNotContain("\r", text);
    }
}
