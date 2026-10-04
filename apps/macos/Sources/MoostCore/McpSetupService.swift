import Foundation

/// MCP 設定の登録・解除・自己診断（Issue #45 の Dart 実装 `McpSetupService` の移植）。
///
/// アプリ内蔵 MCP サーバー（`<MoostApp> mcp`）を Claude Code / Codex CLI /
/// Claude Desktop へワンクリックで連携登録する。
///
/// - Claude Code / Codex CLI は `<cli> mcp add` / `mcp remove` / `mcp get`
///   サブコマンドを使う（`mcp get` の終了コードで登録済みか判定）。
/// - Claude Desktop は CLI サブコマンドが無いため、設定 JSON
///   `~/Library/Application Support/Claude/claude_desktop_config.json` の
///   `mcpServers.moost` キーだけをマージする（他社製 MCP サーバーの
///   設定は壊さない。既存キーは保持する）。
///
/// バイナリのパスは配布形態（.app 同梱 / 開発ビルド）で異なるため、
/// 呼び出し側（App 層）が実行中バイナリのパスを解決して渡す。
public enum McpSetupError: Error, Equatable {
    case commandNotFound(String)
    case processFailed(String)
    case invalidJson(String)
}

public struct McpSetupService: Sendable {
    /// 外部コマンド実行の結果（テストで差し替え可能）。
    public typealias Runner = @Sendable (String, [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

    private let runner: Runner
    private let claudeOverride: String
    private let codexOverride: String
    private let claudeDesktopConfigPath: String

    public init(
        runner: Runner? = nil,
        claudeOverride: String = "",
        codexOverride: String = "",
        home: String? = nil,
        claudeDesktopConfigPath: String? = nil
    ) {
        let homeValue = home ?? ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.runner = runner ?? McpSetupService.defaultRunner
        self.claudeOverride = claudeOverride
        self.codexOverride = codexOverride
        self.claudeDesktopConfigPath = claudeDesktopConfigPath
            ?? homeValue + "/Library/Application Support/Claude/claude_desktop_config.json"
    }

    /// プロセスを起動して終了コードと標準出力を取る既定実装。
    public static func defaultRunner(_ executable: String, _ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do {
            try p.run()
        } catch {
            throw McpSetupError.processFailed("failed to start \(executable): \(error.localizedDescription)")
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (
            p.terminationStatus,
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    // MARK: - Claude Code

    public func isClaudeCodeConnected() -> Bool {
        guard let claude = AgentPathDetect.claude(override: claudeOverride) else { return false }
        guard let result = try? runner(claude, ["mcp", "get", "moost"]) else { return false }
        return result.exitCode == 0
    }

    public func registerClaudeCode(binaryPath: String) throws {
        let claude = try requireClaude()
        try runOrThrow(claude, ["mcp", "add", "-s", "user", "moost", "--"] + [binaryPath, "mcp"])
    }

    public func unregisterClaudeCode() throws {
        let claude = try requireClaude()
        try runOrThrow(claude, ["mcp", "remove", "moost", "-s", "user"])
    }

    // MARK: - Codex CLI

    public func isCodexConnected() -> Bool {
        guard let codex = AgentPathDetect.codex(override: codexOverride) else { return false }
        guard let result = try? runner(codex, ["mcp", "get", "moost"]) else { return false }
        return result.exitCode == 0
    }

    public func registerCodex(binaryPath: String) throws {
        let codex = try requireCodex()
        try runOrThrow(codex, ["mcp", "add", "moost", "--"] + [binaryPath, "mcp"])
    }

    public func unregisterCodex() throws {
        let codex = try requireCodex()
        try runOrThrow(codex, ["mcp", "remove", "moost"])
    }

    // MARK: - Claude Desktop

    /// `claude_desktop_config.json` に `mcpServers.moost` キーが存在するか。
    public func isClaudeDesktopConnected() -> Bool {
        guard let config = try? readDesktopConfig() else { return false }
        guard let servers = config["mcpServers"] as? [String: Any] else { return false }
        return servers["moost"] != nil
    }

    /// `mcpServers.moost` だけを追記/更新する（他社製サーバーの設定は保持）。
    public func registerClaudeDesktop(binaryPath: String) throws {
        var config: [String: Any] = [:]
        if let existing = try readDesktopConfig() {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["moost"] = ["command": binaryPath, "args": ["mcp"]]
        config["mcpServers"] = servers
        try writeDesktopConfig(config)
    }

    /// `mcpServers.moost` キーだけを削除する（他社製サーバーの設定は保持）。
    public func unregisterClaudeDesktop() throws {
        guard let decoded = try? readDesktopConfig() else { return }
        guard var servers = decoded["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "moost")
        var config = decoded
        config["mcpServers"] = servers
        try writeDesktopConfig(config)
    }

    // MARK: - 自己診断

    /// `<binaryPath> mcp` を起動し initialize ハンドシェイクが通るかを確認する。
    public func selfTest(binaryPath: String, timeout: TimeInterval = 5) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["mcp"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardInput = stdinPipe
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do {
            try p.run()
        } catch {
            return false
        }
        let requestId = Int(Date().timeIntervalSince1970 * 1000)
        let request = "{\"jsonrpc\":\"2.0\",\"id\":\(requestId),\"method\":\"initialize\"," +
            "\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{}," +
            "\"clientInfo\":{\"name\":\"moost-selftest\",\"version\":\"1\"}}}\n"
        stdinPipe.fileHandleForWriting.write(Data(request.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        var found = false
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var buffer = Data()
            var found = false
        }
        let box = Box()
        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                semaphore.signal()
                return
            }
            box.buffer.append(data)
            guard let text = String(data: box.buffer, encoding: .utf8) else { return }
            if text.contains("\"id\":\(requestId)") && text.contains("\"result\"") {
                box.found = true
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        handle.readabilityHandler = nil
        if p.isRunning {
            p.terminate()
        }
        found = box.found
        return found
    }

    // MARK: - 内部

    private func requireClaude() throws -> String {
        guard let path = AgentPathDetect.claude(override: claudeOverride) else {
            throw McpSetupError.commandNotFound("claude command not found")
        }
        return path
    }

    private func requireCodex() throws -> String {
        guard let path = AgentPathDetect.codex(override: codexOverride) else {
            throw McpSetupError.commandNotFound("codex command not found")
        }
        return path
    }

    private func runOrThrow(_ executable: String, _ arguments: [String]) throws {
        let result: (exitCode: Int32, stdout: String, stderr: String)
        do {
            result = try runner(executable, arguments)
        } catch let error as McpSetupError {
            throw error
        } catch {
            throw McpSetupError.processFailed("failed to start \(executable): \(error.localizedDescription)")
        }
        if result.exitCode != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? result.stdout : result.stderr
            throw McpSetupError.processFailed(
                detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "exit code \(result.exitCode)" : detail)
        }
    }

    /// 設定ファイルを読む。ファイルが無い / 空の場合は nil。
    /// 壊れた JSON・オブジェクト以外の場合は invalidJson を投げる（上書きしない）。
    private func readDesktopConfig() throws -> [String: Any]? {
        let url = URL(fileURLWithPath: claudeDesktopConfigPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let decoded = try? MoostJSON.parse(text) else {
            throw McpSetupError.invalidJson("\(claudeDesktopConfigPath) is not valid JSON. Fix or remove it manually before retrying.")
        }
        guard let config = decoded as? [String: Any] else {
            throw McpSetupError.invalidJson("\(claudeDesktopConfigPath) does not contain a JSON object")
        }
        return config
    }

    private func writeDesktopConfig(_ config: [String: Any]) throws {
        let url = URL(fileURLWithPath: claudeDesktopConfigPath)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let text = MoostJSON.serialize(config, pretty: true) + "\n"
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw McpSetupError.processFailed("failed to write \(claudeDesktopConfigPath): \(error.localizedDescription)")
        }
    }
}
