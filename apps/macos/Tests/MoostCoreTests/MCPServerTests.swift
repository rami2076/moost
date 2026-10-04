import XCTest
@testable import MoostCore

/// MCPServer（`moost mcp` の stdio JSON-RPC）のテスト。
/// リファレンス実装: apps/mcp_server/test/moost_mcp_server_test.dart の mirror。
/// Swift 側は MCP SDK を使わず Foundation のみで実装しているため、
/// ここでは JSON-RPC の行単位の入出力（MemoryMCPChannel）で検証する。
final class MCPServerTests: XCTestCase {
    private var tempDir: URL!
    private var home: String!
    private var server: MCPServer!

    private var memoFile: URL { tempDir.appendingPathComponent("memos.json") }
    private var projectFile: URL { tempDir.appendingPathComponent("projects.json") }
    private var settingsFile: URL { tempDir.appendingPathComponent("settings.json") }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_mcp_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        home = tempDir.path
        server = MCPServer(
            home: home, serverVersion: "test-version",
            memoStore: MemoStore(file: memoFile),
            projectStore: ProjectStore(file: projectFile),
            settingsStore: SettingsStore(file: settingsFile))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - helpers

    private func request(_ method: String, params: [String: Any]? = nil,
                         id: Any = 1) -> [String: Any] {
        var request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params {
            request["params"] = params
        }
        return request
    }

    /// 1 行のリクエストを処理し、レスポンス（通知なら nil）を返す。
    private func handle(_ request: [String: Any]) -> [String: Any]? {
        let channel = MemoryMCPChannel([encode(request)])
        server.serve(channel: channel)
        return channel.outputLines.first.map(decode)
    }

    private func handle(_ method: String, params: [String: Any]? = nil) -> [String: Any]? {
        handle(request(method, params: params))
    }

    /// ツール呼び出し（tools/call）のショートカット。
    private func callTool(_ name: String, arguments: [String: Any] = [:]) -> [String: Any]? {
        handle("tools/call", params: ["name": name, "arguments": arguments])
    }

    private func encode(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object),
               encoding: String.Encoding.utf8)!
    }

    private func decode(_ line: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    }

    private func toolNames(from response: [String: Any]) -> Set<String> {
        let result = response["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]
        return Set(tools.map { $0["name"] as! String })
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
    }

    private func writeClaudeHistory() throws {
        try writeText([
            "{\"display\":\"older claude\",\"timestamp\":1000,\"project\":\"/work/alpha\",\"sessionId\":\"S1\"}",
            "{\"display\":\"newer claude\",\"timestamp\":2000,\"project\":\"/work/beta\",\"sessionId\":\"S2\"}",
        ].joined(separator: "\n"),
        to: tempDir.appendingPathComponent(".claude/history.jsonl"))
    }

    private func writePiSession(sessionId: String) throws {
        // pi のセッション（2026-03-01）。claude より新しい時刻にする。
        try writeText([
            "{\"type\":\"session\",\"version\":2,\"id\":\"\(sessionId)\","
                + "\"timestamp\":\"2026-03-01T00:00:00.000Z\",\"cwd\":\"/work/pi\"}",
            "{\"type\":\"message\",\"id\":\"m1\",\"parentId\":null,"
                + "\"timestamp\":\"2026-03-01T00:00:01.000Z\",\"message\":{\"role\":\"user\","
                + "\"content\":[{\"type\":\"text\",\"text\":\"pi の最新プロンプト\"}]}}",
        ].joined(separator: "\n"),
        to: tempDir.appendingPathComponent(
            ".pi/agent/sessions/2026-03-01T00-00-00_\(sessionId).jsonl"))
    }

    // MARK: - プロトコル

    func test_initialize_returns_server_info_and_capabilities() throws {
        let response = try XCTUnwrap(handle(request("initialize",
                                                   params: [
                                                       "protocolVersion": "2025-06-18",
                                                       "capabilities": [:],
                                                       "clientInfo": ["name": "test", "version": "0"],
                                                   ])))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(response["id"] as? Int, 1)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "moost")
        XCTAssertEqual(serverInfo["version"] as? String, "test-version")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
    }

    func test_ping_returns_empty_result() throws {
        let response = try XCTUnwrap(handle("ping"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertTrue(result.isEmpty)
    }

    func test_initialized_notification_gets_no_response() throws {
        let channel = MemoryMCPChannel([
            "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
        ])
        server.serve(channel: channel)
        XCTAssertEqual(channel.outputLines.count, 0)
    }

    func test_unknown_method_returns_method_not_found() throws {
        let response = try XCTUnwrap(handle("frobnicate"))
        XCTAssertNil(response["result"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertTrue((error["message"] as? String)?.contains("frobnicate") == true)
    }

    func test_invalid_json_returns_parse_error_with_null_id() throws {
        let channel = MemoryMCPChannel(["this is not json"])
        server.serve(channel: channel)
        let response = try XCTUnwrap(channel.outputLines.first.map(decode))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32700)
        XCTAssertTrue(response["id"] is NSNull)
    }

    // MARK: - tools/list

    func test_tools_list_exposes_exactly_the_four_tools() throws {
        let response = try XCTUnwrap(handle("tools/list"))
        let names = toolNames(from: response)
        XCTAssertEqual(names, [
            "list_recent_sessions",
            "list_memos",
            "list_registered_projects",
            "get_resume_command",
        ])
        // inputSchema の契約（openai 系クライアントも読める形）
        let tools = (response["result"] as! [String: Any])["tools"] as! [[String: Any]]
        let resume = try XCTUnwrap(tools.first { ($0["name"] as? String) == "get_resume_command" })
        let schema = try XCTUnwrap(resume["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertEqual(required, ["agent", "projectPath", "sessionId"])
    }

    // MARK: - list_recent_sessions

    func test_list_recent_sessions_merges_adapters_newest_first_and_respects_limit() throws {
        try writeClaudeHistory()
        try writePiSession(sessionId: "sess-pi")

        // limit 1: 最新（pi）だけ
        let one = try XCTUnwrap(callTool("list_recent_sessions", arguments: ["limit": 1]))
        let oneResult = try XCTUnwrap(one["result"] as? [String: Any])
        let oneContent = try XCTUnwrap(oneResult["content"] as? [[String: Any]])
        let oneItems = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data((oneContent[0]["text"] as! String).utf8))
                as? [[String: Any]])
        XCTAssertEqual(oneItems.count, 1)
        XCTAssertEqual(oneItems[0]["agent"] as? String, "pi")
        XCTAssertEqual(oneItems[0]["sessionId"] as? String, "sess-pi")
        XCTAssertEqual(oneItems[0]["title"] as? String, "pi の最新プロンプト")

        // limit 2: pi / claude (2000) の順
        let two = try XCTUnwrap(callTool("list_recent_sessions", arguments: ["limit": 2]))
        let twoResult = try XCTUnwrap(two["result"] as? [String: Any])
        let twoContent = try XCTUnwrap(twoResult["content"] as? [[String: Any]])
        let twoItems = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data((twoContent[0]["text"] as! String).utf8))
                as? [[String: Any]])
        XCTAssertEqual(twoItems.map { $0["agent"] as? String }, ["pi", "claude-code"])
        XCTAssertEqual(twoItems[1]["sessionId"] as? String, "S2")
    }

    // MARK: - list_memos

    func test_list_memos_returns_stored_memos() throws {
        let store = MemoStore(file: memoFile)
        let memo = Memo(
            id: "m1", agent: "claude-code", sessionId: "s1", title: "タイトル",
            tags: ["tag1"], body: "本文", projectPath: "/work/p",
            createdAt: ISOUTC.parse("2026-01-01T00:00:00.000Z") ?? Date(),
            updatedAt: ISOUTC.parse("2026-01-02T00:00:00.000Z") ?? Date())
        try store.add(memo)

        let response = try XCTUnwrap(callTool("list_memos"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let items = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8))
                as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        // Memo.toJson() と同じキー（createdAt/updatedAt は ISOUTC 形式）
        XCTAssertEqual(items[0]["id"] as? String, "m1")
        XCTAssertEqual(items[0]["title"] as? String, "タイトル")
        XCTAssertEqual(items[0]["tags"] as? [String], ["tag1"])
        XCTAssertEqual(items[0]["createdAt"] as? String, "2026-01-01T00:00:00.000Z")
    }

    // MARK: - list_registered_projects

    func test_list_registered_projects_returns_display_name() throws {
        let store = ProjectStore(file: projectFile)
        try store.save([
            Project(id: "p1", projectPath: "/Users/me/work",
                    createdAt: ISOUTC.parse("2026-01-01T00:00:00.000Z") ?? Date()),
        ])

        let response = try XCTUnwrap(callTool("list_registered_projects"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let items = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8))
                as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["id"] as? String, "p1")
        XCTAssertEqual(items[0]["projectPath"] as? String, "/Users/me/work")
        XCTAssertEqual(items[0]["displayName"] as? String, "work")
    }

    // MARK: - get_resume_command

    func test_get_resume_command_builds_codex_command() throws {
        let response = try XCTUnwrap(callTool("get_resume_command", arguments: [
            "agent": "codex",
            "projectPath": "/work/p",
            "sessionId": "s1",
        ]))
        XCTAssertNil(response["error"])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[0]["text"] as? String)
        // shellEscape はシングルクォートで包む（Dart の shellEscape と同じ）
        XCTAssertEqual(text, "cd '/work/p' && codex resume 's1'")
    }

    func test_get_resume_command_claude_uses_unset_prefix() throws {
        let response = try XCTUnwrap(callTool("get_resume_command", arguments: [
            "agent": "claude-code",
            "projectPath": "/work/p",
            "sessionId": "s1",
        ]))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[0]["text"] as? String)
        // claude は内部環境変数を env -u で除外してから起動する（Issue #52）
        XCTAssertTrue(text.hasPrefix("cd '/work/p' && env -u"), "got: \(text)")
        XCTAssertTrue(text.contains("claude --resume 's1'"))
    }

    func test_get_resume_command_pi_uses_settings_provider_and_model() throws {
        var settings = Settings()
        settings.piProvider = "openai"
        settings.piModel = "gpt-test"
        try SettingsStore(file: settingsFile).save(settings)

        let response = try XCTUnwrap(callTool("get_resume_command", arguments: [
            "agent": "pi",
            "projectPath": "/work/p",
            "sessionId": "s1",
        ]))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content[0]["text"] as? String)
        XCTAssertEqual(
            text,
            "cd '/work/p' && pi --session 's1' --provider 'openai' --model 'gpt-test'")
    }

    func test_get_resume_command_unknown_agent_is_tool_error() throws {
        let response = try XCTUnwrap(callTool("get_resume_command", arguments: [
            "agent": "unknown-agent",
            "projectPath": "/p",
            "sessionId": "s1",
        ]))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertTrue(((content[0]["text"] as? String) ?? "").contains("unknown-agent"))
    }

    func test_get_resume_command_missing_arguments_is_invalid_params() throws {
        let response = try XCTUnwrap(callTool("get_resume_command", arguments: ["agent": "codex"]))
        XCTAssertNil(response["result"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }

    func test_call_unknown_tool_is_invalid_params() throws {
        let response = try XCTUnwrap(callTool("delete_everything"))
        XCTAssertNil(response["result"])
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }
}

/// テスト用のメモリ内チャネル（行の配列を入力し、出力を収集する）。
final class MemoryMCPChannel: MCPLineChannel {
    private let inputLines: [String]
    private var index = 0
    var outputLines: [String] = []

    init(_ inputLines: [String]) {
        self.inputLines = inputLines
    }

    func readLine() -> String? {
        guard index < inputLines.count else { return nil }
        defer { index += 1 }
        return inputLines[index]
    }

    func writeLine(_ line: String) {
        outputLines.append(line)
    }
}
