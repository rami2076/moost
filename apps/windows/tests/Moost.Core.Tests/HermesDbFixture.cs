using Microsoft.Data.Sqlite;

namespace Moost.Core.Tests;

/// <summary>
/// Hermes の <c>state.db</c> をテスト用に組み立てる。
/// スキーマは hermes-agent v0.22.3 の実機観測（macOS 実装のクエリ）に合わせている。
/// </summary>
internal static class HermesDbFixture
{
    /// <summary>空の DB を作る（テーブルだけ）。</summary>
    public static string Create(string path)
    {
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
            // プールするとハンドルが残り、テスト後のファイル読み取りが失敗する
            Pooling = false,
        }.ToString());
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                title TEXT,
                cwd TEXT,
                started_at REAL,
                last_activity_at REAL,
                source TEXT,
                message_count INTEGER DEFAULT 0,
                archived INTEGER DEFAULT 0,
                hidden INTEGER DEFAULT 0
            );
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                role TEXT,
                content TEXT,
                timestamp REAL,
                active INTEGER DEFAULT 1,
                tool_name TEXT
            );
            """;
        command.ExecuteNonQuery();

        return path;
    }

    /// <summary>セッション 1 件を追加する。</summary>
    public static void AddSession(
        string path,
        string id,
        string title,
        string cwd,
        double activitySeconds,
        string source = "local",
        int messageCount = 1,
        int archived = 0,
        int hidden = 0)
    {
        Execute(path, """
            INSERT INTO sessions (id, title, cwd, started_at, last_activity_at, source,
                                  message_count, archived, hidden)
            VALUES ($id, $title, $cwd, $started, $activity, $source, $count, $archived, $hidden)
            """,
            ("$id", id), ("$title", title), ("$cwd", cwd),
            ("$started", activitySeconds - 10), ("$activity", activitySeconds),
            ("$source", source), ("$count", messageCount),
            ("$archived", archived), ("$hidden", hidden));
    }

    /// <summary>メッセージを追加する。</summary>
    public static void AddMessage(
        string path,
        string sessionId,
        string role,
        string content,
        double timestampSeconds,
        string? toolName = null,
        int active = 1)
    {
        Execute(path, """
            INSERT INTO messages (session_id, role, content, timestamp, active, tool_name)
            VALUES ($session, $role, $content, $timestamp, $active, $tool)
            """,
            ("$session", sessionId), ("$role", role), ("$content", content),
            ("$timestamp", timestampSeconds), ("$active", active), ("$tool", toolName));
    }

    private static void Execute(string path, string sql, params (string Name, object? Value)[] parameters)
    {
        using var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
            // プールするとハンドルが残り、テスト後のファイル読み取りが失敗する
            Pooling = false,
        }.ToString());
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = sql;
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value ?? DBNull.Value);
        }

        command.ExecuteNonQuery();
    }
}
