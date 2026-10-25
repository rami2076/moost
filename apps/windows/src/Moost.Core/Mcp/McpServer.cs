using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>MCP の 1 行チャネル（実運用は標準入出力・テストはメモリ実装）。</summary>
public interface IMcpChannel
{
    /// <summary>次の 1 行を読む。EOF で null。</summary>
    string? ReadLine();

    /// <summary>1 行（JSON-RPC メッセージ）を書き出す。</summary>
    void WriteLine(string line);
}

/// <summary>標準入出力に接続するチャネル（<c>moost mcp</c> の実運用経路）。</summary>
public sealed class StdioMcpChannel : IMcpChannel
{
    private readonly TextReader _input;
    private readonly TextWriter _output;

    public StdioMcpChannel()
    {
        // MCP は UTF-8 の JSON Lines。BOM を付けず、行ごとに flush する
        var stdout = Console.OpenStandardOutput();
        _output = new StreamWriter(stdout, new UTF8Encoding(false)) { AutoFlush = true };
        _input = Console.In;
    }

    public string? ReadLine() => _input.ReadLine();

    public void WriteLine(string line) => _output.WriteLine(line);
}

/// <summary>
/// <c>moost mcp</c>（アプリ内蔵 MCP サーバー・ADR-005）の最小実装（stdio JSON-RPC 2.0）。
/// リファレンス実装: <c>apps/macos/Sources/MoostCore/MCPServer.swift</c>。
///
/// 公開するツールは <b>読み取り専用の 4 つ</b>:
/// <list type="bullet">
/// <item><c>list_recent_sessions</c> 直近セッション（limit 任意・既定 20）</item>
/// <item><c>list_memos</c> 登録済みメモ</item>
/// <item><c>list_registered_projects</c> 登録プロジェクト</item>
/// <item><c>get_resume_command</c> 復帰コマンドの組み立て</item>
/// </list>
/// エージェント側データへの書き込みは一切しない。
/// </summary>
public sealed class McpServer
{
    // 日本語を \uXXXX に膨らませない（MCP のコンテキスト消費を抑える・UTF-8 のまま出す）
    private static readonly JsonSerializerOptions CompactOptions = new()
    {
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly SessionSources _sources;
    private readonly MemoStore _memos;
    private readonly ProjectStore _projects;
    private readonly SettingsStore _settingsStore;
    private readonly string _serverVersion;

    public McpServer(
        SessionSources? sources = null,
        MemoStore? memos = null,
        ProjectStore? projects = null,
        SettingsStore? settings = null,
        string serverVersion = "0.1.0")
    {
        _sources = sources ?? SessionSources.FromHome();
        _memos = memos ?? MemoStore.DefaultLocation();
        _projects = projects ?? ProjectStore.DefaultLocation();
        _settingsStore = settings ?? SettingsStore.DefaultLocation();
        _serverVersion = serverVersion;
    }

    /// <summary>EOF まで読み続ける（<c>moost mcp</c> の本体）。</summary>
    public void Run(IMcpChannel channel)
    {
        while (channel.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var response = HandleLine(line);
            if (response is not null)
            {
                channel.WriteLine(response);
            }
        }
    }

    /// <summary>1 行を処理して応答（JSON）を返す。応答不要なら null。</summary>
    public string? HandleLine(string line)
    {
        JsonNode? request;
        try
        {
            request = JsonNode.Parse(line);
        }
        catch (JsonException)
        {
            return ErrorResponse(null, -32700, "Parse error");
        }

        if (request is not JsonObject message)
        {
            return ErrorResponse(null, -32600, "Invalid Request");
        }

        var id = message["id"]?.DeepClone();
        if (!JsonRead.TryString(message, "method", out var method))
        {
            // 通知（id なし）は応答しない
            return id is null ? null : ErrorResponse(id, -32600, "Invalid Request");
        }

        // 通知（id なし）には応答しない（JSON-RPC 2.0）
        if (id is null && method is "notifications/initialized" or "initialized")
        {
            return null;
        }

        return method switch
        {
            "initialize" => InitializeResponse(id),
            "ping" => SuccessResponse(id, new JsonObject()),
            "tools/list" => SuccessResponse(id, new JsonObject { ["tools"] = ToolDefinitions() }),
            "tools/call" => HandleToolCall(id, message["params"] as JsonObject),
            _ => ErrorResponse(id, -32601, $"Method not found: {method}"),
        };
    }

    private string InitializeResponse(JsonNode? id)
    {
        var result = new JsonObject
        {
            ["protocolVersion"] = "2024-11-05",
            ["capabilities"] = new JsonObject
            {
                ["tools"] = new JsonObject { ["listChanged"] = false },
            },
            ["serverInfo"] = new JsonObject
            {
                ["name"] = "moost",
                ["version"] = _serverVersion,
            },
        };
        return SuccessResponse(id, result);
    }

    private static JsonArray ToolDefinitions() =>
    [
        new JsonObject
        {
            ["name"] = "list_recent_sessions",
            ["description"] = "Claude Code / Codex / pi / hermes の直近セッションを最新順に一覧する。",
            ["inputSchema"] = new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["limit"] = new JsonObject
                    {
                        ["type"] = "integer",
                        ["description"] = "取得件数の上限（デフォルト 20）",
                    },
                },
            },
        },
        new JsonObject
        {
            ["name"] = "list_memos",
            ["description"] = "登録済みのメモを一覧する。",
            ["inputSchema"] = new JsonObject { ["type"] = "object", ["properties"] = new JsonObject() },
        },
        new JsonObject
        {
            ["name"] = "list_registered_projects",
            ["description"] = "セッション履歴がまだないディレクトリでも登録しておける「登録プロジェクト」を一覧する。",
            ["inputSchema"] = new JsonObject { ["type"] = "object", ["properties"] = new JsonObject() },
        },
        new JsonObject
        {
            ["name"] = "get_resume_command",
            ["description"] = "指定したセッションへ復帰するためのシェルコマンドを組み立てる。",
            ["inputSchema"] = new JsonObject
            {
                ["type"] = "object",
                ["properties"] = new JsonObject
                {
                    ["agent"] = new JsonObject
                    {
                        ["type"] = "string",
                        ["description"] = "エージェント種別（claude-code / codex / pi / hermes）",
                    },
                    ["projectPath"] = new JsonObject
                    {
                        ["type"] = "string",
                        ["description"] = "復帰先ディレクトリの絶対パス",
                    },
                    ["sessionId"] = new JsonObject
                    {
                        ["type"] = "string",
                        ["description"] = "復帰するセッションの ID",
                    },
                },
                ["required"] = new JsonArray("agent", "sessionId"),
            },
        },
    ];

    private string HandleToolCall(JsonNode? id, JsonObject? parameters)
    {
        if (parameters is null || !JsonRead.TryString(parameters, "name", out var name))
        {
            return ErrorResponse(id, -32602, "Missing tool name");
        }

        var arguments = parameters["arguments"] as JsonObject;
        return name switch
        {
            "list_recent_sessions" => ToolResult(id, ListRecentSessions(arguments)),
            "list_memos" => ToolResult(id, ListMemos()),
            "list_registered_projects" => ToolResult(id, ListRegisteredProjects()),
            "get_resume_command" => GetResumeCommand(id, arguments),
            _ => ErrorResponse(id, -32602, $"Unknown tool: {name}"),
        };
    }

    private string ListRecentSessions(JsonObject? arguments)
    {
        var limit = 20;
        if (arguments?["limit"] is JsonValue value && value.TryGetValue<int>(out var requested) && requested > 0)
        {
            limit = requested;
        }

        var sessions = SessionAggregator.RecentSessions(_sources, limit);
        var items = new JsonArray();
        foreach (var session in sessions)
        {
            items.Add(new JsonObject
            {
                ["agent"] = session.AgentId,
                ["sessionId"] = session.SessionId,
                ["projectPath"] = session.ProjectPath,
                ["title"] = session.DisplayTitle,
                ["updatedAt"] = IsoUtc.Format(session.UpdatedAt),
            });
        }

        return Serialize(items);
    }

    private string ListMemos()
    {
        var items = new JsonArray();
        foreach (var memo in _memos.Load())
        {
            items.Add(memo.ToJson());
        }

        return Serialize(items);
    }

    private string ListRegisteredProjects()
    {
        var items = new JsonArray();
        foreach (var project in _projects.Load())
        {
            var json = project.ToJson();
            json["displayName"] = project.DisplayName;
            items.Add(json);
        }

        return Serialize(items);
    }

    private string GetResumeCommand(JsonNode? id, JsonObject? arguments)
    {
        if (arguments is null
            || !JsonRead.TryString(arguments, "agent", out var agent)
            || !JsonRead.TryString(arguments, "sessionId", out var sessionId))
        {
            return ErrorResponse(id, -32602, "agent と sessionId は必須です");
        }

        var projectPath = JsonRead.TryString(arguments, "projectPath", out var path) ? path : string.Empty;
        var settings = _settingsStore.Load();
        var command = ResumeCommand.Resume(agent, projectPath, sessionId, settings.PiProvider, settings.PiModel);
        if (command is null)
        {
            return ErrorResponse(id, -32602, $"Unknown agent: {agent}");
        }

        return ToolResult(id, Serialize(new JsonObject { ["command"] = command }));
    }

    private static string ToolResult(JsonNode? id, string text) =>
        SuccessResponse(id, new JsonObject
        {
            ["content"] = new JsonArray(new JsonObject
            {
                ["type"] = "text",
                ["text"] = text,
            }),
            ["isError"] = false,
        });

    private static string SuccessResponse(JsonNode? id, JsonNode result) =>
        new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id?.DeepClone(),
            ["result"] = result,
        }.ToJsonString(CompactOptions);

    private static string ErrorResponse(JsonNode? id, int code, string message) =>
        new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id?.DeepClone(),
            ["error"] = new JsonObject
            {
                ["code"] = code,
                ["message"] = message,
            },
        }.ToJsonString(CompactOptions);

    private static string Serialize(JsonNode node) => node.ToJsonString(CompactOptions);
}
