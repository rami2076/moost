import XCTest
@testable import MoostCore

/// Issue #132: Hermes（~/.hermes/config.yaml の mcp_servers）と
/// Zed（~/.config/zed/settings.json の context_servers、JSONC）への
/// 登録・削除・状態判定。全てフィクスチャファイルに対して行い、
/// 実 HOME の設定ファイルには一切触れない（パスは注入）。
final class McpSetupHermesZedTests: XCTestCase {
    private var tempDir: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-setup-132-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
    }

    private var hermesConfigPath: String { tempDir + "/hermes-config.yaml" }
    private var zedSettingsPath: String { tempDir + "/zed-settings.json" }

    private func hermesService() -> McpSetupService {
        McpSetupService(runner: nil,
                        claudeOverride: "/usr/bin/true",
                        codexOverride: "/usr/bin/true",
                        hermesOverride: "/usr/bin/true",
                        home: tempDir,
                        hermesConfigPath: hermesConfigPath,
                        zedSettingsPath: zedSettingsPath)
    }

    private func zedService() -> McpSetupService {
        McpSetupService(runner: nil,
                        claudeOverride: "/usr/bin/true",
                        codexOverride: "/usr/bin/true",
                        hermesOverride: "/usr/bin/true",
                        home: tempDir,
                        hermesConfigPath: hermesConfigPath,
                        zedSettingsPath: zedSettingsPath)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    // MARK: - Hermes: 状態判定

    func testHermesNotConnectedWithoutFile() {
        XCTAssertFalse(hermesService().isHermesConnected())
    }

    func testHermesNotConnectedWhenServersCommentedOut() throws {
        // 実機の config.yaml は mcp_servers 節がコメント例のみ（v0.22.3 実機形状）。
        let fixture = """
        _config_version: 53
        database:
          journal_mode: "wal"
        # mcp_servers:
        #   time:
        #     command: uvx
        #     args: ["mcp-server-time"]
        providers:
          dspark:
            base_url: http://example:8888/v1
        """
        try write(fixture, to: hermesConfigPath)
        XCTAssertFalse(hermesService().isHermesConnected(), "コメントアウトされた節は未登録")
    }

    func testHermesConnectedWithOtherServers() throws {
        let fixture = """
        # Hermes config
        _config_version: 53

        # MCP servers
        mcp_servers:
          time:
            command: uvx
            args: ["mcp-server-time"]
          moost:
            command: "/opt/moost/MoostApp"
            args: ["mcp"]
            enabled: true

        providers:
          dspark:
            base_url: http://example:8888/v1
        """
        try write(fixture, to: hermesConfigPath)
        XCTAssertTrue(hermesService().isHermesConnected())
    }

    func testHermesNotConnectedWhenDisabled() throws {
        let fixture = """
        mcp_servers:
          moost:
            command: "/opt/moost/MoostApp"
            args: ["mcp"]
            enabled: false
        """
        try write(fixture, to: hermesConfigPath)
        XCTAssertFalse(hermesService().isHermesConnected(), "enabled: false は未登録扱い")
    }

    // MARK: - Hermes: 登録（マージが壊れないこと）

    func testHermesRegisterKeepsCommentsOtherServersAndSections() throws {
        let fixture = """
        # Hermes Agent CLI Configuration
        _config_version: 53

        # =============================================================================
        # Database Configuration
        # =============================================================================
        database:
          journal_mode: "wal"  # comment kept
          # wal_autocheckpoint: 1000

        # MCP servers go here:
        mcp_servers:
          # time server (existing)
          time:
            command: uvx
            args: ["mcp-server-time"]
          github:
            command: npx
            args: ["-y", "@modelcontextprotocol/server-github"]
            env:
              GITHUB_PERSONAL_ACCESS_TOKEN: "ghp_example"

        providers:
          dspark:
            base_url: http://example:8888/v1
        """
        try write(fixture, to: hermesConfigPath)

        try hermesService().registerHermes(binaryPath: "/opt/moost/MoostApp")

        let after = try read(hermesConfigPath)
        // 既存内容は行単位で完全に保持される（行レベルマージ）。
        for requiredLine in fixture.split(separator: "\n") {
            XCTAssertTrue(after.contains(String(requiredLine)),
                          "既存行が失われた: \(requiredLine)")
        }
        // moost エントリが追加され、Hermes が保存する形と同一であること。
        // 追加位置は mcp_servers 直下（サブキーと同じ 2 字インデント）。
        XCTAssertTrue(after.contains("\n  moost:\n"))
        XCTAssertTrue(after.contains(#"    command: "/opt/moost/MoostApp""#))
        XCTAssertTrue(after.contains(#"    args: ["mcp"]"#))
        XCTAssertTrue(after.contains("    enabled: true"))
        XCTAssertTrue(hermesService().isHermesConnected())
    }

    func testHermesRegisterIntoMissingSectionAppendsAtEnd() throws {
        let fixture = """
        _config_version: 53
        providers:
          dspark:
            base_url: http://example:8888/v1
        """
        try write(fixture, to: hermesConfigPath)
        try hermesService().registerHermes(binaryPath: "/opt/moost/MoostApp")
        let after = try read(hermesConfigPath)
        XCTAssertTrue(after.hasPrefix(fixture), "既存内容は先頭のまま")
        XCTAssertTrue(after.contains("mcp_servers:\n  moost:\n    command: \"/opt/moost/MoostApp\"\n    args: [\"mcp\"]\n    enabled: true\n"))
        XCTAssertTrue(hermesService().isHermesConnected())
    }

    func testHermesRegisterCreatesFileWhenMissing() throws {
        try hermesService().registerHermes(binaryPath: "/Applications/Moost.app/Contents/MacOS/MoostApp")
        let after = try read(hermesConfigPath)
        XCTAssertEqual(after,
                       "mcp_servers:\n  moost:\n    command: \"/Applications/Moost.app/Contents/MacOS/MoostApp\"\n    args: [\"mcp\"]\n    enabled: true\n")
        XCTAssertTrue(hermesService().isHermesConnected())
    }

    func testHermesRegisterIsIdempotent() throws {
        let fixture = """
        mcp_servers:
          time:
            command: uvx
            args: ["mcp-server-time"]
        """
        try write(fixture, to: hermesConfigPath)
        let service = hermesService()
        try service.registerHermes(binaryPath: "/opt/moost/MoostApp")
        let once = try read(hermesConfigPath)
        try service.registerHermes(binaryPath: "/opt/moost/MoostApp")
        let twice = try read(hermesConfigPath)
        XCTAssertEqual(once, twice, "2回登録しても重複しない（差し替え）")
        XCTAssertEqual(once.components(separatedBy: "  moost:").count - 1, 1)
        // 更新（パス変更）も効く。
        try service.registerHermes(binaryPath: "/new/path/MoostApp")
        let updated = try read(hermesConfigPath)
        XCTAssertTrue(updated.contains(#""/new/path/MoostApp""#))
        XCTAssertFalse(updated.contains("Moost.app"))
        XCTAssertTrue(updated.contains(#"    command: "/new/path/MoostApp""#))
        XCTAssertFalse(updated.contains(#""/opt/moost/MoostApp""#))
    }

    // MARK: - Hermes: 削除

    func testHermesUnregisterRemovesOnlyMoost() throws {
        let fixture = """
        # header comment
        mcp_servers:
          # time server (existing)
          time:
            command: uvx
            args: ["mcp-server-time"]
          moost:
            command: "/opt/moost/MoostApp"
            args: ["mcp"]
            enabled: true
          github:
            command: npx
            args: ["-y", "@modelcontextprotocol/server-github"]

        providers:
          dspark:
            base_url: http://example:8888/v1
        """
        try write(fixture, to: hermesConfigPath)
        try hermesService().unregisterHermes()

        let after = try read(hermesConfigPath)
        XCTAssertFalse(after.contains("moost"), "moost エントリだけが消える")
        for requiredLine in ["# header comment",
                             "# time server (existing)",
                             "    command: uvx",
                             "    args: [\"mcp-server-time\"]",
                             "    command: npx",
                             "providers:",
                             "    base_url: http://example:8888/v1"] {
            XCTAssertTrue(after.contains(requiredLine), "失われた: \(requiredLine)")
        }
        XCTAssertFalse(hermesService().isHermesConnected())
    }

    func testHermesUnregisterWithoutMoostIsNoop() throws {
        let fixture = """
        mcp_servers:
          time:
            command: uvx
            args: ["mcp-server-time"]
        """
        try write(fixture, to: hermesConfigPath)
        try hermesService().unregisterHermes()
        // moost が無い状態は無変更（末尾改行の正規化のみ許容）。
        XCTAssertEqual(try read(hermesConfigPath), fixture + "\n", "moost が無い状態は無変更")
    }

    func testHermesUnregisterWithoutFileIsNoop() throws {
        try hermesService().unregisterHermes() // 例外なし
        XCTAssertFalse(FileManager.default.fileExists(atPath: hermesConfigPath))
    }

    func testHermesRegisterPathWithSpecialCharsQuoted() throws {
        try hermesService().registerHermes(binaryPath: "/Applications/Mo ost.app/Contents/MacOS/MoostApp")
        let after = try read(hermesConfigPath)
        XCTAssertTrue(after.contains(#""/Applications/Mo ost.app/Contents/MacOS/MoostApp""#),
                      "スペース入りパスはクォートされる")
        XCTAssertTrue(hermesService().isHermesConnected())
    }

    // MARK: - Zed: 状態判定

    func testZedNotConnectedWithoutFile() {
        XCTAssertFalse(zedService().isZedConnected())
    }

    func testZedNotConnectedWhenOnlyAutoDisabled() throws {
        // Zed は「一時無効」を auto_disable: false で表す → 未登録扱い。
        let fixture = """
        {
          // disabled for now
          "context_servers": {
            "moost": { "command": "/opt/moost/MoostApp", "args": ["mcp"], "auto_disable": false },
          },
        }
        """
        try write(fixture, to: zedSettingsPath)
        XCTAssertFalse(zedService().isZedConnected())
    }

    // MARK: - Zed: 登録（JSONC を壊さずマージできること）

    /// 実機の settings.json 形状（先頭コメント + 入れ子オブジェクト）。
    /// ここでは JSONC パーサ検証用に /* */・行内 //・trailing comma を追加した。
    private let zedFixture = """
    // Zed settings
    //
    // For information on how to configure Zed, see the Zed
    // documentation: https://zed.dev/docs/configuring-zed
    {
      /* block comment */
      "cli_default_open_behavior": "existing_window",
      "project_panel": {
        "dock": "left",   // inline comment
      },
      "theme": {
        "mode": "system",
        "light": "Catppuccin Mocha",
        "dark": "Catppuccin Macchiato",
      },
      "context_servers": {
        "other": { "command": "/usr/bin/other", "args": [], },
      },
    }
    """

    func testZedRegisterParsesJSONCAndKeepsOtherSettings() throws {
        try write(zedFixture, to: zedSettingsPath)
        try zedService().registerZed(binaryPath: "/opt/moost/MoostApp")

        let after = try read(zedSettingsPath)
        // 書き戻しは再シリアライズなのでコメントは保持しない（Issue #132 で明記した妥協）。
        XCTAssertFalse(after.contains("Zed settings"))
        // 書き戻した内容が再び有効な JSON として読めること。
        let decoded = try MoostJSON.parse(after)
        let config = try XCTUnwrap(decoded as? [String: Any])
        // 既存キーは保持。
        XCTAssertEqual(config["cli_default_open_behavior"] as? String, "existing_window")
        let panel = try XCTUnwrap(config["project_panel"] as? [String: Any])
        XCTAssertEqual(panel["dock"] as? String, "left")
        let theme = try XCTUnwrap(config["theme"] as? [String: Any])
        XCTAssertEqual(theme["dark"] as? String, "Catppuccin Macchiato")
        // 他サーバー定義は保持、moost が追加。
        let servers = try XCTUnwrap(config["context_servers"] as? [String: Any])
        XCTAssertNotNil(servers["other"], "他サーバー定義は保持される")
        let moost = try XCTUnwrap(servers["moost"] as? [String: Any])
        XCTAssertEqual(moost["command"] as? String, "/opt/moost/MoostApp")
        XCTAssertEqual(moost["args"] as? [String], ["mcp"])
        XCTAssertTrue(zedService().isZedConnected())
    }

    func testZedRegisterCreatesFileWhenMissing() throws {
        try zedService().registerZed(binaryPath: "/opt/moost/MoostApp")
        let decoded = try MoostJSON.parse(try read(zedSettingsPath))
        let config = try XCTUnwrap(decoded as? [String: Any])
        let servers = try XCTUnwrap(config["context_servers"] as? [String: Any])
        XCTAssertNotNil(servers["moost"])
    }

    func testZedRegisterIsIdempotent() throws {
        try write(zedFixture, to: zedSettingsPath)
        let service = zedService()
        try service.registerZed(binaryPath: "/opt/moost/MoostApp")
        let once = try read(zedSettingsPath)
        try service.registerZed(binaryPath: "/opt/moost/MoostApp")
        let twice = try read(zedSettingsPath)
        XCTAssertEqual(once, twice, "2回登録しても重複しない（キー差し替え）")
        // 更新（パス変更）も効く。
        try service.registerZed(binaryPath: "/new/path/MoostApp")
        XCTAssertTrue(try read(zedSettingsPath).contains("/new/path/MoostApp"))
    }

    func testZedUnregisterRemovesOnlyMoost() throws {
        try write(zedFixture, to: zedSettingsPath)
        let service = zedService()
        try service.registerZed(binaryPath: "/opt/moost/MoostApp")
        try service.unregisterZed()

        let decoded = try MoostJSON.parse(try read(zedSettingsPath))
        let config = try XCTUnwrap(decoded as? [String: Any])
        let servers = try XCTUnwrap(config["context_servers"] as? [String: Any])
        XCTAssertNil(servers["moost"])
        XCTAssertNotNil(servers["other"])
        // 他の設定キーは保持。
        XCTAssertEqual(config["cli_default_open_behavior"] as? String, "existing_window")
        XCTAssertFalse(service.isZedConnected())
    }

    func testZedUnregisterWithoutFileIsNoop() throws {
        try zedService().unregisterZed() // 例外なし
        XCTAssertFalse(FileManager.default.fileExists(atPath: zedSettingsPath))
    }

    func testZedRegisterOverCorruptJsonThrows() throws {
        try write("{ not valid json", to: zedSettingsPath)
        XCTAssertThrowsError(try zedService().registerZed(binaryPath: "/opt/moost/MoostApp")) { error in
            guard case McpSetupError.invalidJson = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try read(zedSettingsPath), "{ not valid json", "壊れた JSONC は上書きしない")
    }

    // MARK: - JSONC パーサ単体

    func testStripJSONCHandlesCommentsInsideStrings() throws {
        let jsonc = """
        {
          "url": "https://example.com/mcp", // trailing note
          /* block */
          "note": "a // not a comment, /* nor this */",
        }
        """
        let stripped = McpSetupService.stripJSONC(jsonc)
        let decoded = try MoostJSON.parse(stripped)
        let obj = try XCTUnwrap(decoded as? [String: Any])
        XCTAssertEqual(obj["url"] as? String, "https://example.com/mcp")
        XCTAssertEqual(obj["note"] as? String, "a // not a comment, /* nor this */")
    }

    func testStripJSONCStripsTrailingCommas() throws {
        let jsonc = """
        {
          "a": [1, 2, 3,],
          "b": {"c": 1,},
        }
        """
        let stripped = McpSetupService.stripJSONC(jsonc)
        _ = try MoostJSON.parse(stripped)
    }
}
