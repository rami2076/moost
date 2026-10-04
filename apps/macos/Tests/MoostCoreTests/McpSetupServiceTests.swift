import XCTest
@testable import MoostCore

final class McpSetupServiceTests: XCTestCase {
    private var tempDir: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-setup-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
    }

    private var desktopConfigPath: String {
        tempDir + "/claude_desktop_config.json"
    }

    /// 引数を記録して指定の終了コードを返す fake runner。
    private final class RecordingRunner: @unchecked Sendable {
        var calls: [(executable: String, arguments: [String])] = []
        var exitCode: Int32 = 0
        var stdout: String = ""
        var stderr: String = ""

        func call(_ executable: String, _ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
            calls.append((executable, arguments))
            return (exitCode, stdout, stderr)
        }
    }

    // MARK: - Claude Code

    func testRegisterClaudeCodeArguments() throws {
        let runner = RecordingRunner()
        let service = McpSetupService(
            runner: runner.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.registerClaudeCode(binaryPath: "/opt/moost/MoostApp")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "/usr/bin/true")
        XCTAssertEqual(runner.calls[0].arguments,
                       ["mcp", "add", "-s", "user", "moost", "--", "/opt/moost/MoostApp", "mcp"])
    }

    func testClaudeCodeConnectedTrueAndFalse() {
        let connected = RecordingRunner()
        connected.exitCode = 0
        let serviceConnected = McpSetupService(
            runner: connected.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        XCTAssertTrue(serviceConnected.isClaudeCodeConnected())
        XCTAssertEqual(connected.calls[0].arguments, ["mcp", "get", "moost"])

        let disconnected = RecordingRunner()
        disconnected.exitCode = 1
        let serviceDisconnected = McpSetupService(
            runner: disconnected.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        XCTAssertFalse(serviceDisconnected.isClaudeCodeConnected())
    }

    func testUnregisterClaudeCodeArguments() throws {
        let runner = RecordingRunner()
        let service = McpSetupService(
            runner: runner.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.unregisterClaudeCode()
        XCTAssertEqual(runner.calls[0].arguments, ["mcp", "remove", "moost", "-s", "user"])
    }

    // MARK: - Codex

    func testRegisterCodexArguments() throws {
        let runner = RecordingRunner()
        let service = McpSetupService(
            runner: runner.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.registerCodex(binaryPath: "/opt/moost/MoostApp")
        XCTAssertEqual(runner.calls[0].executable, "/usr/bin/true")
        XCTAssertEqual(runner.calls[0].arguments,
                       ["mcp", "add", "moost", "--", "/opt/moost/MoostApp", "mcp"])
    }

    func testUnregisterCodexArguments() throws {
        let runner = RecordingRunner()
        let service = McpSetupService(
            runner: runner.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.unregisterCodex()
        XCTAssertEqual(runner.calls[0].arguments, ["mcp", "remove", "moost"])
    }

    // MARK: - Claude Desktop

    func testDesktopRegisterCreatesFileAndKeepsOthers() throws {
        // 既存設定（他社製サーバーあり）を用意
        let existing = """
        {
          "mcpServers": {
            "other": { "command": "/usr/bin/other" },
            "moost": { "command": "/old/MoostApp", "args": ["mcp"] }
          }
        }
        """
        try Data(existing.utf8).write(to: URL(fileURLWithPath: desktopConfigPath))

        let service = McpSetupService(
            runner: nil,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.registerClaudeDesktop(binaryPath: "/opt/moost/MoostApp")

        let decoded = try MoostJSON.parse(
            String(data: Data(contentsOf: URL(fileURLWithPath: desktopConfigPath)), encoding: .utf8) ?? "")
        let config = try XCTUnwrap(decoded as? [String: Any])
        let servers = try XCTUnwrap(config["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["other"], "他社製サーバーは保持される")
        let moost = try XCTUnwrap(servers["moost"] as? [String: Any])
        XCTAssertEqual(moost["command"] as? String, "/opt/moost/MoostApp")
        XCTAssertEqual(moost["args"] as? [String], ["mcp"])
        XCTAssertTrue(service.isClaudeDesktopConnected())
    }

    func testDesktopUnregisterRemovesOnlyMoost() throws {
        let existing = """
        {
          "mcpServers": {
            "other": { "command": "/usr/bin/other" },
            "moost": { "command": "/opt/moost/MoostApp", "args": ["mcp"] }
          }
        }
        """
        try Data(existing.utf8).write(to: URL(fileURLWithPath: desktopConfigPath))

        let service = McpSetupService(
            runner: nil,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        try service.unregisterClaudeDesktop()

        let decoded = try MoostJSON.parse(
            String(data: Data(contentsOf: URL(fileURLWithPath: desktopConfigPath)), encoding: .utf8) ?? "")
        let config = try XCTUnwrap(decoded as? [String: Any])
        let servers = try XCTUnwrap(config["mcpServers"] as? [String: Any])
        XCTAssertNil(servers["moost"])
        XCTAssertNotNil(servers["other"])
        XCTAssertFalse(service.isClaudeDesktopConnected())
    }

    func testDesktopConnectedWithoutFile() {
        let service = McpSetupService(
            runner: nil,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        XCTAssertFalse(service.isClaudeDesktopConnected())
    }

    func testDesktopRegisterOverCorruptJsonThrows() throws {
        try Data("{ not valid json".utf8).write(to: URL(fileURLWithPath: desktopConfigPath))
        let service = McpSetupService(
            runner: nil,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        // v1 と同じく、壊れた JSON は例外にして上書きしない（安全側）。
        XCTAssertThrowsError(try service.registerClaudeDesktop(binaryPath: "/opt/moost/MoostApp")) { error in
            guard case McpSetupError.invalidJson = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        let content = try String(contentsOf: URL(fileURLWithPath: desktopConfigPath), encoding: .utf8)
        XCTAssertEqual(content, "{ not valid json", "壊れた JSON は上書きしない")
    }

    // MARK: - プロセス失敗

    func testRunFailureThrowsProcessFailed() {
        let runner = RecordingRunner()
        runner.exitCode = 2
        runner.stderr = "boom"
        let service = McpSetupService(
            runner: runner.call,
            claudeOverride: "/usr/bin/true",
            codexOverride: "/usr/bin/true",
            claudeDesktopConfigPath: desktopConfigPath)
        XCTAssertThrowsError(try service.unregisterClaudeCode()) { error in
            guard case McpSetupError.processFailed(let detail) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(detail, "boom")
        }
    }
}
