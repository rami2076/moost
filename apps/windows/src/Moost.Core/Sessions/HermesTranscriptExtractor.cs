using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Moost.Core;

/// <summary>
/// Hermes の会話抜粋（要約用テキスト）を作る。
/// リファレンス実装: <c>HermesTranscriptExtractor</c>（Swift）。
///
/// Hermes はヘッドレス要約コマンドを持たないため、抽出結果をそのまま要約として返す
/// （pi と同じ方針・API 消費ゼロ）。DB は<b>読み取り専用</b>で開く。
/// </summary>
public sealed class HermesTranscriptExtractor
{
    private readonly string _databasePath;

    public HermesTranscriptExtractor(string databasePath)
    {
        _databasePath = databasePath;
    }

    /// <summary>
    /// セッションのやり取りをテキスト化して返す（DB・セッションが無ければ空文字列）。
    /// <paramref name="full"/> が false なら末尾 <paramref name="rallies"/> ラリー、true なら全体。
    /// </summary>
    public string Extract(string sessionId, bool full = false, int rallies = 1)
    {
        if (!File.Exists(_databasePath))
        {
            return string.Empty;
        }

        try
        {
            var rows = ReadMessages(sessionId);
            if (rows.Count == 0)
            {
                return string.Empty;
            }

            var collected = new List<Rally>();
            foreach (var row in rows)
            {
                switch (row.Role)
                {
                    case "user":
                    {
                        var text = row.Content.Trim();
                        if (text.Length == 0)
                        {
                            continue;
                        }

                        collected.Add(new Rally(text));
                        if (!full && collected.Count > rallies)
                        {
                            // メモリを抑えるため保持は直近分だけにする
                            collected.RemoveAt(0);
                        }

                        break;
                    }

                    case "assistant":
                    {
                        var text = row.Content.Trim();
                        if (text.Length == 0 || collected.Count == 0)
                        {
                            continue;
                        }

                        collected[^1].Followups.Add(("Assistant", text));
                        break;
                    }

                    case "tool":
                    {
                        if (collected.Count == 0)
                        {
                            continue;
                        }

                        var output = ToolOutput(row.Content);
                        if (output.Length == 0)
                        {
                            continue;
                        }

                        var label = string.IsNullOrEmpty(row.ToolName) ? "tool" : row.ToolName;
                        collected[^1].Followups.Add(($"Tool({label})", output));
                        break;
                    }
                }
            }

            return collected.Count == 0 ? string.Empty : Rally.Render(collected);
        }
        catch (SqliteException)
        {
            return string.Empty;
        }
        catch (IOException)
        {
            return string.Empty;
        }
        catch (UnauthorizedAccessException)
        {
            return string.Empty;
        }
    }

    private List<HermesMessageRow> ReadMessages(string sessionId)
    {
        var connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = _databasePath,
            Mode = SqliteOpenMode.ReadOnly,
            Cache = SqliteCacheMode.Shared,
            Pooling = false,
        }.ToString();

        using var connection = new SqliteConnection(connectionString);
        connection.Open();

        using (var pragma = connection.CreateCommand())
        {
            pragma.CommandText = "PRAGMA query_only = ON;";
            pragma.ExecuteNonQuery();
        }

        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT role, COALESCE(content, ''), COALESCE(tool_name, '')
            FROM messages
            WHERE session_id = $id AND COALESCE(active, 1) = 1
            ORDER BY timestamp ASC, id ASC
            """;
        command.Parameters.AddWithValue("$id", sessionId);

        var rows = new List<HermesMessageRow>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            rows.Add(new HermesMessageRow(reader.GetString(0), reader.GetString(1), reader.GetString(2)));
        }

        return rows;
    }

    /// <summary>
    /// tool 行の content（JSON: <c>{"output": ..., "exit_code": ...}</c>）から出力を取り出す。
    /// JSON でない場合は raw をそのまま使う。
    /// </summary>
    private static string ToolOutput(string content)
    {
        var trimmed = content.Trim();
        if (trimmed.Length == 0)
        {
            return string.Empty;
        }

        if (JsonlLine.TryParseObject(trimmed, out var json)
            && JsonRead.TryString(json, "output", out var output))
        {
            return output.Trim();
        }

        return trimmed;
    }

    private sealed record HermesMessageRow(string Role, string Content, string ToolName);
}
