import Foundation

/// `moost mcp`（アプリ内蔵 MCP サーバー）の stdio チャネル契約。
/// 実運用は [StdioMCPChannel]、テストはメモリ実装を注入する。
public protocol MCPLineChannel {
    /// 次の 1 行を読む。EOF で nil を返す。
    func readLine() -> String?
    /// 1 行（JSON-RPC メッセージ）を書き出す（改行はチャネルが付与する）。
    func writeLine(_ line: String)
}

/// 標準入出力に接続するチャネル（`moost mcp` の実運用経路）。
public final class StdioMCPChannel: MCPLineChannel {
    public init() {}

    public func readLine() -> String? {
        // 標準入力の行読み（C ストリーム）。EOF で nil。
        return Swift.readLine()
    }

    public func writeLine(_ line: String) {
        // NSFileHandle の write は直接 OS へ書く（バッファされない）。
        // synchronizeFile() はパイプで Invalid argument になるため使わない。
        let data = (line + "\n").data(using: String.Encoding.utf8) ?? Data()
        FileHandle.standardOutput.write(data)
    }
}

/// MCP サーバー（stdio JSON-RPC 2.0 の超最小実装）。
/// リファレンス実装: apps/mcp_server/lib/src/moost_mcp_server.dart（Issue #43）。
/// MCP SDK（dart_mcp）に相当する部分を Foundation だけで賄う。
///
/// 公開するツール（読み取り専用、書き込み系はまだ無い）:
/// - list_recent_sessions: 直近セッションを最新順に
/// - list_memos: 登録済みメモ
/// - list_registered_projects: 登録プロジェクト
/// - get_resume_command: 復帰コマンドの組み立て
public final class MCPServer {
    public let home: String
    public let serverVersion: String

    private let memoStore: MemoStore
    private let projectStore: ProjectStore
    private let settingsStore: SettingsStore

    /// すべての注入を省略すると `~/.moost/v2/` の実ファイルを読む。
    public init(
        home: String,
        serverVersion: String = "0.1.0",
        memoStore: MemoStore? = nil,
        projectStore: ProjectStore? = nil,
        settingsStore: SettingsStore? = nil
    ) {
        self.home = home
        self.serverVersion = serverVersion
        self.memoStore = memoStore ?? MemoStore(file: MCPServer.storeURL(home: home, name: "memos.json"))
        self.projectStore = projectStore ?? ProjectStore(file: MCPServer.storeURL(home: home, name: "projects.json"))
        self.settingsStore = settingsStore ?? SettingsStore(file: MCPServer.storeURL(home: home, name: "settings.json"))
    }

    private static func storeURL(home: String, name: String) -> URL {
        URL(fileURLWithPath: home + "/.moost/v2/" + name, isDirectory: false)
    }

    /// EOF までリクエストを読み、レスポンスを書き出す（ブロッキング）。
    public func serve(channel: MCPLineChannel) {
        while let line = channel.readLine() {
            guard let response = handleJSONLine(line) else { continue }
            channel.writeLine(response)
        }
    }

    /// 1 行の JSON-RPC を処理し、レスポンスの JSON 文字列を返す。
    /// 通知（id なし）や解析不能な行は nil（応答しない）。
    public func handleJSONLine(_ line: String) -> String? {
        guard let data = line.data(using: String.Encoding.utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return errorResponse(id: nil, code: -32700, message: "Parse error")
        }
        guard let method = object["method"] as? String else {
            return errorResponse(id: object["id"], code: -32600, message: "Invalid Request")
        }
        let id = object["id"]
        let params = object["params"] as? [String: Any] ?? [:]

        // 通知（id なし）はレスポンスを返さない
        guard let responseID = id, !(id is NSNull) else {
            handleNotification(method: method, params: params)
            return nil
        }

        switch method {
        case "initialize":
            return response(responseID, result: initializeResult(protocolVersion: params["protocolVersion"] as? String))
        case "ping":
            return response(responseID, result: [:])
        case "tools/list":
            return response(responseID, result: ["tools": toolDefinitions()])
        case "tools/call":
            return handleToolCall(id: responseID, params: params)
        default:
            return errorResponse(id: responseID, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// 通知は現状すべて無視してよい（initialized / cancelled 等）。
    private func handleNotification(method: String, params: [String: Any]) {
        // 初期化済み通知・キャンセル通知は何もしない
    }

    // MARK: - MCP メソッド

    private func initializeResult(protocolVersion: String?) -> [String: Any] {
        // クライアントが提示した版をそのまま返す（2025-06-18 までの版のみ）。
        // 未知の版は最新版で応答する（仕様上許容される）。
        let version = protocolVersion ?? "2025-06-18"
        return [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "moost", "version": serverVersion],
        ]
    }

    // MARK: - ツール定義（Dart リファレンスと同形）

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "list_recent_sessions",
                "description": "Claude Code / Codex の直近セッションを最新順に一覧する。",
                "inputSchema": schema(properties: [
                    "limit": ["type": "integer", "description": "取得件数の上限（デフォルト 20）"],
                ]),
            ],
            [
                "name": "list_memos",
                "description": "登録済みのメモを一覧する。",
                "inputSchema": schema(properties: [:]),
            ],
            [
                "name": "list_registered_projects",
                "description": "セッション履歴がまだないディレクトリでも登録しておける「登録プロジェクト」を一覧する。",
                "inputSchema": schema(properties: [:]),
            ],
            [
                "name": "get_resume_command",
                "description": "指定したセッションへ復帰するためのシェルコマンドを組み立てる。",
                "inputSchema": schema(
                    properties: [
                        "agent": ["type": "string", "description": "エージェント種別（例: \"claude-code\", \"codex\"）"],
                        "projectPath": ["type": "string", "description": "復帰先ディレクトリの絶対パス"],
                        "sessionId": ["type": "string", "description": "復帰するセッションの ID"],
                    ],
                    required: ["agent", "projectPath", "sessionId"]),
            ],
        ]
    }

    private func schema(properties: [String: Any], required: [String] = []) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
    }

    // MARK: - tools/call

    private func handleToolCall(id: Any, params: [String: Any]) -> String {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "list_recent_sessions":
            return toolResult(id: id, text: listRecentSessions(arguments))
        case "list_memos":
            return toolResult(id: id, text: listMemos())
        case "list_registered_projects":
            return toolResult(id: id, text: listRegisteredProjects())
        case "get_resume_command":
            return getResumeCommand(id: id, arguments: arguments)
        default:
            return errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
    }

    private func listRecentSessions(_ arguments: [String: Any]) -> String {
        let limit = (arguments["limit"] as? NSNumber)?.intValue ?? 20
        let sessions = SessionAggregator.recentSessions(homeDirectory: home, limit: limit)
        let items: [[String: Any]] = sessions.map { session in
            [
                "agent": session.agentId,
                "sessionId": session.sessionId,
                "projectPath": session.projectPath,
                "title": session.displayTitle,
                "updatedAt": ISOUTC.format(session.updatedAt),
            ]
        }
        return encodeJSON(items)
    }

    private func listMemos() -> String {
        let memos = (try? memoStore.load()) ?? []
        return encodeJSON(memos.map { $0.toJson() })
    }

    private func listRegisteredProjects() -> String {
        let projects = (try? projectStore.load()) ?? []
        let items: [[String: Any]] = projects.map { project in
            var json = project.toJson()
            json["displayName"] = project.displayName
            return json
        }
        return encodeJSON(items)
    }

    private func getResumeCommand(id: Any, arguments: [String: Any]) -> String {
        guard let agent = arguments["agent"] as? String,
              let projectPath = arguments["projectPath"] as? String,
              let sessionId = arguments["sessionId"] as? String
        else {
            return errorResponse(id: id, code: -32602,
                                 message: "agent / projectPath / sessionId are required")
        }
        let settings = (try? settingsStore.load()) ?? Settings()
        guard let command = ResumeCommand.resume(
            agent: agent, projectPath: projectPath, sessionId: sessionId,
            provider: settings.piProvider, model: settings.piModel)
        else {
            // 未知エージェントは MCP のツールレベルのエラー（Dart と同じ形）
            return toolResult(id: id, text: "unknown agent: \(agent)", isError: true)
        }
        return toolResult(id: id, text: command)
    }

    // MARK: - JSON-RPC 組立

    private func response(_ id: Any, result: [String: Any]) -> String {
        encodeJSON([
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ])
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> String {
        var base: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id {
            base["id"] = id
        } else {
            base["id"] = NSNull()
        }
        return encodeJSON(base)
    }

    /// MCP ツール呼び出しの結果（content テキスト 1 個）。
    private func toolResult(id: Any, text: String, isError: Bool = false) -> String {
        var result: [String: Any] = [
            "content": [["type": "text", "text": text]],
        ]
        if isError {
            result["isError"] = true
        }
        return response(id, result: result)
    }

    private func encodeJSON(_ object: Any) -> String {
        // ツール結果は配列（[[String: Any]]）でも辞書（[String: Any]）でも通す
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: String.Encoding.utf8)
        else {
            return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}"
        }
        return text
    }
}
