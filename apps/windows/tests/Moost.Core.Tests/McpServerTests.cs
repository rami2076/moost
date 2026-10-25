using System.Text.Json.Nodes;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// アプリ内蔵 MCP サーバー（<c>moost mcp</c>・#104）。stdio の代わりにメモリチャネルで検証する。
/// </summary>
public class McpServerTests
{
    private sealed class MemoryChannel : IMcpChannel
    {
        private readonly Queue<string> _input;
        private readonly List<string> _output = [];

        public MemoryChannel(params string[] lines) => _input = new Queue<string>(lines);

        public IReadOnlyList<string> Output => _output;

        public string? ReadLine() => _input.Count > 0 ? _input.Dequeue() : null;

        public void WriteLine(string line) => _output.Add(line);
    }

    private static McpServer Create(TempDir dir)
    {
        var sources = new SessionSources
        {
            ClaudeHistoryFile = dir.File("claude-history.jsonl"),
            ClaudeProjectsDirectory = Path.Combine(dir.Path, "p"),
            CodexHistoryFile = dir.File("c"),
            CodexSessionsDirectory = Path.Combine(dir.Path, "cs"),
            PiSessionsDirectory = Path.Combine(dir.Path, "ps"),
            HermesDatabase = dir.File("state.db"),
        };

        File.WriteAllLines(sources.ClaudeHistoryFile,
        [
            """{"display":"mcp prompt","timestamp":1000,"project":"C:\\work\\mcp","sessionId":"S1"}""",
        ]);

        var memos = new MemoStore(dir.File("memos.json"));
        memos.Add(new Memo
        {
            Id = "m1",
            Agent = ResumeCommand.ClaudeAgentId,
            SessionId = "S1",
            Title = "MCP 用メモ",
            Tags = ["mcp"],
            Body = "本文",
            ProjectPath = "C:\\work\\mcp",
            CreatedAt = new DateTime(2026, 10, 25, 0, 0, 0, DateTimeKind.Utc),
            UpdatedAt = new DateTime(2026, 10, 25, 0, 0, 0, DateTimeKind.Utc),
        });

        var projects = new ProjectStore(dir.File("projects.json"));
        projects.Add(new Project
        {
            Id = "p1",
            ProjectPath = "C:\\work\\registered",
            CreatedAt = new DateTime(2026, 10, 25, 0, 0, 0, DateTimeKind.Utc),
        });

        return new McpServer(sources, memos, projects, new SettingsStore(dir.File("settings.json")), "9.9.9");
    }

    private static JsonObject Parse(string line) => JsonNode.Parse(line)!.AsObject();

    private static string TextOf(JsonObject response) =>
        response["result"]!["content"]!.AsArray()[0]!["text"]!.GetValue<string>();

    [Fact]
    public void Initialize_ReturnsServerInfoAndToolsCapability()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine("""{"jsonrpc":"2.0","id":1,"method":"initialize"}""")!);

        Assert.Equal("2.0", response["jsonrpc"]!.GetValue<string>());
        Assert.Equal(1, response["id"]!.GetValue<int>());
        Assert.Equal("moost", response["result"]!["serverInfo"]!["name"]!.GetValue<string>());
        Assert.Equal("9.9.9", response["result"]!["serverInfo"]!["version"]!.GetValue<string>());
        Assert.NotNull(response["result"]!["capabilities"]!["tools"]);
    }

    [Fact]
    public void ToolsList_ExposesFourReadOnlyTools()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine("""{"jsonrpc":"2.0","id":2,"method":"tools/list"}""")!);

        var names = response["result"]!["tools"]!.AsArray()
            .Select(tool => tool!["name"]!.GetValue<string>())
            .ToArray();

        Assert.Equal(
            ["list_recent_sessions", "list_memos", "list_registered_projects", "get_resume_command"],
            names);
    }

    [Fact]
    public void ListRecentSessions_ReturnsJsonArray()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine(
            """{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_recent_sessions","arguments":{"limit":5}}}""")!);

        var items = JsonNode.Parse(TextOf(response))!.AsArray();
        var session = items[0]!.AsObject();

        Assert.Equal("S1", session["sessionId"]!.GetValue<string>());
        Assert.Equal("claude-code", session["agent"]!.GetValue<string>());
        Assert.Equal("C:\\work\\mcp", session["projectPath"]!.GetValue<string>());
    }

    [Fact]
    public void ListMemos_ReturnsStoredMemos()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine(
            """{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_memos"}}""")!);

        var items = JsonNode.Parse(TextOf(response))!.AsArray();
        Assert.Equal("MCP 用メモ", items[0]!["title"]!.GetValue<string>());
    }

    [Fact]
    public void ListRegisteredProjects_AddsDerivedDisplayName()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine(
            """{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_registered_projects"}}""")!);

        var items = JsonNode.Parse(TextOf(response))!.AsArray();
        Assert.Equal("registered", items[0]!["displayName"]!.GetValue<string>());
    }

    [Fact]
    public void GetResumeCommand_BuildsPowerShellCommand()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine(
            """{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_resume_command","arguments":{"agent":"claude-code","projectPath":"C:\\work\\mcp","sessionId":"S1"}}}""")!);

        var command = JsonNode.Parse(TextOf(response))!["command"]!.GetValue<string>();
        Assert.StartsWith("Set-Location -LiteralPath 'C:\\work\\mcp'; ", command, StringComparison.Ordinal);
        Assert.Contains("claude --resume 'S1'", command, StringComparison.Ordinal);
    }

    [Fact]
    public void GetResumeCommand_RequiresAgentAndSessionId()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine(
            """{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_resume_command","arguments":{"agent":"claude-code"}}}""")!);

        Assert.Equal(-32602, response["error"]!["code"]!.GetValue<int>());
    }

    [Fact]
    public void UnknownToolAndMethod_ReturnErrors()
    {
        using var dir = new TempDir();
        var server = Create(dir);

        var unknownTool = Parse(server.HandleLine(
            """{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"delete_everything"}}""")!);
        Assert.Equal(-32602, unknownTool["error"]!["code"]!.GetValue<int>());

        var unknownMethod = Parse(server.HandleLine("""{"jsonrpc":"2.0","id":9,"method":"nope"}""")!);
        Assert.Equal(-32601, unknownMethod["error"]!["code"]!.GetValue<int>());
    }

    [Fact]
    public void ParseError_IsReported()
    {
        using var dir = new TempDir();
        var response = Parse(Create(dir).HandleLine("{ this is not json")!);

        Assert.Equal(-32700, response["error"]!["code"]!.GetValue<int>());
    }

    [Fact]
    public void Notifications_GetNoResponse()
    {
        using var dir = new TempDir();
        Assert.Null(Create(dir).HandleLine("""{"jsonrpc":"2.0","method":"notifications/initialized"}"""));
    }

    [Fact]
    public void Run_ProcessesUntilEof_AndSkipsEmptyLines()
    {
        using var dir = new TempDir();
        var channel = new MemoryChannel(
            """{"jsonrpc":"2.0","id":1,"method":"ping"}""",
            "",
            """{"jsonrpc":"2.0","id":2,"method":"tools/list"}""");

        Create(dir).Run(channel);

        Assert.Equal(2, channel.Output.Count);
        Assert.All(channel.Output, line => Assert.Contains("\"jsonrpc\":\"2.0\"", line, StringComparison.Ordinal));
    }

    [Fact]
    public void ReadOnlyTools_DoNotModifyStores()
    {
        using var dir = new TempDir();
        var memosPath = dir.File("memos.json");
        var server = Create(dir);
        var before = File.ReadAllBytes(memosPath);

        _ = server.HandleLine("""{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_memos"}}""");
        _ = server.HandleLine("""{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_recent_sessions"}}""");

        Assert.Equal(before, File.ReadAllBytes(memosPath));
    }
}
