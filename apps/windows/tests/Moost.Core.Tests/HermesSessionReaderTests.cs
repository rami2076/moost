using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// Hermes の <c>state.db</c>（SQLite）読み取り（#101）。DB はテスト用に組み立てる。
/// </summary>
public class HermesSessionReaderTests
{
    [Fact]
    public void ReadsSessions_NewestFirst_WithLastUserPromptAndTitle()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "h-old", "古い表題", "/work/old", 1_700_000_000);
        HermesDbFixture.AddSession(db, "h-new", "新しい表題", "/work/new", 1_700_000_100);
        HermesDbFixture.AddMessage(db, "h-new", "user", "最新の質問", 1_700_000_050);
        HermesDbFixture.AddMessage(db, "h-new", "assistant", "応答", 1_700_000_060);
        HermesDbFixture.AddMessage(db, "h-new", "user", "さらに新しい質問", 1_700_000_090);

        var sessions = new HermesSessionReader(db).RecentSessions();

        Assert.Equal(["h-new", "h-old"], sessions.Select(session => session.SessionId));
        Assert.Equal("さらに新しい質問", sessions[0].LastPrompt);
        Assert.Equal("新しい表題", sessions[0].AiTitle);
        Assert.Equal("/work/new", sessions[0].ProjectPath);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_700_000_100).UtcDateTime,
            sessions[0].UpdatedAt);
    }

    [Fact]
    public void FallsBackToTitle_WhenNoUserMessage()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "h1", "タイトルだけ", "/work/a", 1_700_000_000);

        var session = Assert.Single(new HermesSessionReader(db).RecentSessions());
        Assert.Equal("タイトルだけ", session.LastPrompt);
    }

    [Fact]
    public void ExcludesNonCliSources_EmptySessions_ArchivedAndHidden()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "keep", "", "/w", 1_700_000_000);
        HermesDbFixture.AddSession(db, "gateway", "", "/w", 1_700_000_001, source: "gateway");
        HermesDbFixture.AddSession(db, "empty", "", "/w", 1_700_000_002, messageCount: 0);
        HermesDbFixture.AddSession(db, "archived", "", "/w", 1_700_000_003, archived: 1);
        HermesDbFixture.AddSession(db, "hidden", "", "/w", 1_700_000_004, hidden: 1);
        HermesDbFixture.AddSession(db, "oneshot", "", "/w", 1_700_000_005, source: "oneshot");

        var sessions = new HermesSessionReader(db).RecentSessions();

        Assert.Equal(["oneshot", "keep"], sessions.Select(session => session.SessionId));
    }

    [Fact]
    public void RespectsLimit()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        for (var index = 0; index < 5; index++)
        {
            HermesDbFixture.AddSession(db, $"h{index}", "", "/w", 1_700_000_000 + index);
        }

        var sessions = new HermesSessionReader(db).RecentSessions(limit: 2);

        Assert.Equal(2, sessions.Count);
        Assert.Equal(["h4", "h3"], sessions.Select(session => session.SessionId));
    }

    [Fact]
    public void MissingDatabase_YieldsEmpty()
    {
        using var dir = new TempDir();
        Assert.Empty(new HermesSessionReader(dir.File("no-state.db")).RecentSessions());
    }

    [Fact]
    public void BrokenDatabase_YieldsEmpty_WithoutThrowing()
    {
        using var dir = new TempDir();
        var path = dir.File("state.db");
        File.WriteAllText(path, "this is not a sqlite database");

        Assert.Empty(new HermesSessionReader(path).RecentSessions());
    }

    [Fact]
    public void ReadsWithoutModifyingTheDatabase()
    {
        using var dir = new TempDir();
        var db = HermesDbFixture.Create(dir.File("state.db"));
        HermesDbFixture.AddSession(db, "h1", "", "/w", 1_700_000_000);

        var before = File.ReadAllBytes(db);

        _ = new HermesSessionReader(db).RecentSessions();

        var after = File.ReadAllBytes(db);
        // 読み取り専用で開いているので、DB のバイト列は変化しない
        Assert.Equal(before, after);
    }
}
