using Microsoft.Data.Sqlite;

namespace Moost.Core;

/// <summary>
/// Hermes セッション 1 件分の抽出結果。
/// </summary>
public sealed record HermesSessionEntry
{
    public required string SessionId { get; init; }

    public required string ProjectPath { get; init; }

    public required string LastPrompt { get; init; }

    public required DateTime UpdatedAt { get; init; }

    /// <summary>Hermes が付けた自動タイトル（空なら null）。</summary>
    public string? AiTitle { get; init; }
}

/// <summary>
/// Hermes（Nous Research の自律エージェント）のセッション読み取り。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/HermesSessionReader.swift</c>。
///
/// Hermes は <c>%USERPROFILE%\.hermes\state.db</c>（SQLite・WAL）に全会話を保存する。
/// Moost はこの DB を <b>読み取り専用</b>で開き、<c>sessions</c> / <c>messages</c> から
/// 一覧・最終プロンプトを取る。書き込みは一切しない。
///
/// <list type="bullet">
/// <item>一覧対象: <c>source IN ('local','oneshot')</c>（CLI 起点）かつ <c>message_count &gt; 0</c>（起動スタブ除外）</item>
/// <item>アーカイブ・非表示は除外（<c>archived</c> / <c>hidden</c>）</item>
/// </list>
/// </summary>
public sealed class HermesSessionReader
{
    private readonly string _databasePath;

    public HermesSessionReader(string databasePath)
    {
        _databasePath = databasePath;
    }

    /// <summary>既定の保存先（<c>%USERPROFILE%\.hermes\state.db</c>）を使う。</summary>
    public static HermesSessionReader DefaultLocation(string? userProfile = null) =>
        new(SessionLocations.HermesStateDb(userProfile));

    /// <summary>
    /// 一覧を新しい順で返す。DB が無ければ空（「未インストール」と同じ扱い）。
    /// 読み取りに失敗した場合も空を返す（一覧全体を壊さない）。
    /// </summary>
    public IReadOnlyList<HermesSessionEntry> RecentSessions(int limit = 20)
    {
        if (!File.Exists(_databasePath))
        {
            return [];
        }

        try
        {
            using var connection = OpenReadOnly(_databasePath);
            var rows = QuerySessions(connection, limit);

            var entries = new List<HermesSessionEntry>(rows.Count);
            foreach (var row in rows)
            {
                var lastUser = QueryLastUserMessage(connection, row.Id);
                entries.Add(new HermesSessionEntry
                {
                    SessionId = row.Id,
                    ProjectPath = row.Cwd,
                    // 最終プロンプト = 最後のユーザー発言。無ければタイトルで代用する
                    LastPrompt = lastUser.Length > 0 ? lastUser : row.Title,
                    UpdatedAt = DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Round(row.ActivitySeconds * 1000)).UtcDateTime,
                    AiTitle = row.Title.Length == 0 ? null : row.Title,
                });
            }

            return entries;
        }
        catch (SqliteException)
        {
            return [];
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }

    /// <summary>
    /// 読み取り専用で開く。WAL の DB を他プロセスが使っている場合でも
    /// 書き込みは行わない（<c>Mode=ReadOnly</c>）。
    /// </summary>
    private static SqliteConnection OpenReadOnly(string databasePath)
    {
        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Cache = SqliteCacheMode.Shared,
            // 接続プールを使うとハンドルが残り、Hermes 側の書き込みやファイル操作を
            // 邪魔する可能性がある。読み取りは一覧表示のたびの短時間で済むため都度閉じる。
            Pooling = false,
        }.ToString();

        var connection = new SqliteConnection(connectionString);
        connection.Open();

        // 念のための二重の安全策（この接続からの書き込みを禁止する）
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA query_only = ON;";
        pragma.ExecuteNonQuery();

        return connection;
    }

    private static List<HermesSessionRow> QuerySessions(SqliteConnection connection, int limit)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, COALESCE(title, ''), COALESCE(cwd, ''),
                   COALESCE(last_activity_at, started_at)
            FROM sessions
            WHERE source IN ('local', 'oneshot')
              AND message_count > 0
              AND COALESCE(archived, 0) = 0
              AND COALESCE(hidden, 0) = 0
            ORDER BY COALESCE(last_activity_at, started_at) DESC
            LIMIT $limit
            """;
        command.Parameters.AddWithValue("$limit", limit);

        var rows = new List<HermesSessionRow>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            rows.Add(new HermesSessionRow(
                Id: reader.GetString(0),
                Title: reader.GetString(1),
                Cwd: reader.GetString(2),
                ActivitySeconds: reader.IsDBNull(3) ? 0 : reader.GetDouble(3)));
        }

        return rows;
    }

    private static string QueryLastUserMessage(SqliteConnection connection, string sessionId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT content FROM messages
            WHERE session_id = $id AND role = 'user'
              AND length(trim(COALESCE(content, ''))) > 0
            ORDER BY timestamp DESC, id DESC
            LIMIT 1
            """;
        command.Parameters.AddWithValue("$id", sessionId);

        var result = command.ExecuteScalar();
        return result as string ?? string.Empty;
    }

    private sealed record HermesSessionRow(string Id, string Title, string Cwd, double ActivitySeconds);
}
