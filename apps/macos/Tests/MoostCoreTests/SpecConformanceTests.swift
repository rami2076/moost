import XCTest
@testable import MoostCore

/// spec/conformance.md のチェックリストを共通 Fixture（spec/testdata/）でなぞる
/// native 適合テスト。リファレンス実装 assertion の骨格（packages/core/test/
/// spec_conformance_test.dart）をそのまま写している。このテストに緑でないと
/// native 実装はリリースできない。

private func specRoot() -> URL {
    // `swift test --package-path` でも通るうに、Bundle のリソースを主、cwd 遡上を従にする。
    if let url = Bundle.module.url(forResource: "conformance.md", withExtension: nil) {
        return url.deletingLastPathComponent()
    }
    let fileManager = FileManager.default
    let start = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    for candidate in sequence(first: start) { $0.appendingPathComponent("..") }.prefix(9) {
        let dir = candidate.appendingPathComponent("spec")
        if fileManager.fileExists(atPath: dir.appendingPathComponent("conformance.md").path) {
            return dir
        }
    }
    preconditionFailure("spec/ の Fixture が見つかりません")
}
private func fixtureURL(_ name: String) -> URL {
    specRoot().appendingPathComponent("testdata").appendingPathComponent(name)
}

private func schemaURL(_ name: String) -> URL {
    specRoot().appendingPathComponent("schemas").appendingPathComponent(name + ".schema.json")
}

private func jsonDict(_ url: URL) throws -> [String: Any] {
    var encoding = String.Encoding.utf8
    let text = try String(contentsOf: url, usedEncoding: &encoding)
    let parsed = try MoostJSON.parse(text)
    guard let dict = parsed as? [String: Any] else{
        throw MoostError.malformedJSON("\u{6e}\u{6f}\u{74}\u{20}\u{6f}\u{62}\u{6a}\u{65}\u{63}\u{74}")
    }
    return dict
}

private func makeTempDir(_ label: String) throws -> URL  {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("moost-" + label + "-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
final class SpecConformanceTests: XCTestCase {

    // MARK: spec/schemas

    func test_all_schemas_are_readable_json_with_titles() throws {
        for name in ["memos", "settings", "projects"] {
            let schema = try jsonDict(schemaURL(name))
            let title = schema["title"] as? String ?? ""
            XCTAssertFalse(title.isEmpty, name)
            XCTAssertNotNil(schema["properties"], name)
            XCTAssertNotNil(schema["required"], name)
        }
    }

    // MARK: memos.json（B1-B3, B6）

    func test_memos_valid_fixture_reads_all_entries_with_dangerous_strings_intact() throws {
        let memos = try MemoStore(file: fixtureURL("memos_valid.json")).load()
        XCTAssertEqual(memos.count, 2)
        guard let dangerous = memos.first(where: { $0.agent == "codex" }),
              let first = memos.first(where: { $0.agent == "claude-code" }) else {
            XCTFail("fixture agents missing"); return
        }
        XCTAssertTrue(dangerous.tags.contains("backtick `x`"))
        XCTAssertTrue(dangerous.title.contains("$(whoami)"))
        XCTAssertTrue(dangerous.body.contains("/dev/null"))
        XCTAssertEqual(first.title, "認証リファクタの途中状態")
        XCTAssertEqual(first.tags, ["auth", "wip"])
        XCTAssertEqual(first.updatedAt, ISOUTC.parse("2026-09-21T11:30:00.000Z"))
    }

    func test_memos_corrupt_entry_skips_only_the_broken_entry() throws {
        let memos = try MemoStore(file: fixtureURL("memos_corrupt_entry.json")).load()
        XCTAssertEqual(memos.count, 1)
        XCTAssertEqual(memos.first?.sessionId, "S-OK")
    }

    func test_memo_crud_round_trip_preserves_identity_fields() throws {
        let dir = try makeTempDir("memo-crud")
        let store = MemoStore(file: dir.appendingPathComponent("memos.json"))
        let stamp = ISOUTC.parse("2026-09-01T00:00:00.000Z")!
        let created = Memo(id: "M1", agent: "claude-code", sessionId: "S1", title: "T",
                          tags: ["a"], body: "B", projectPath: "/work",
                          createdAt: stamp, updatedAt: stamp)
        try store.add(created)
        XCTAssertTrue(try store.update("M1", title: "T2"))
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "T2")
        XCTAssertEqual(loaded[0].body, "B")           // 不変項目は保持
        XCTAssertEqual(loaded[0].createdAt, stamp)    // 不変項目は保持
        XCTAssertGreaterThan(loaded[0].updatedAt, stamp) // B4: 可変更新は必ず更新
        XCTAssertTrue(try store.delete("M1"))
        XCTAssertFalse(try store.delete("M1"))
        let raw = try jsonDict(dir.appendingPathComponent("memos.json"))
        XCTAssertEqual(raw["schemaVersion"] as? Int, 1) // B1: envelope
    }

    func test_parse_tags_trims_and_drops_empty() {
        XCTAssertEqual(parseTags("a, b ,,c"), ["a", "b", "c"])
    }

    func test_iso8601_round_trips_with_flutter_side_format() throws {
        let iso = "2026-09-21T11:30:00.000Z"
        guard let date = ISOUTC.parse(iso) else { XCTFail("unparsed"); return }
        XCTAssertEqual(ISOUTC.format(date), iso) // Dart の toUtc().toIso8601String() と相互運用可
    }

    // MARK: JsonFileStore（A2）

    func test_broken_json_is_quarantined_not_overwritten() throws {
        let dir = try makeTempDir("quarantine")
        let file = dir.appendingPathComponent("memos.json")
        try "not json {{{".data(using: .utf8)!.write(to: file, options: .atomic)
        let memos = try MemoStore(file: file).load()
        XCTAssertEqual(memos, [])
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(entries.filter { $0.hasPrefix("memos.json.corrupt-") }.count, 1)
        XCTAssertFalse(entries.contains("memos.json")) // 壊れた元ファイルは消していない
    }

    // MARK: settings.json（C1-C3）

    func test_settings_bad_types_fall_back_per_item() throws {
        let settings = try SettingsStore(file: fixtureURL("settings_bad_types.json")).load()
        XCTAssertEqual(settings, Settings()) // 型違い項目のみデフォルトへ
    }

    func test_settings_missing_file_yields_defaults() throws {
        let settings = try SettingsStore(
            file: URL(fileURLWithPath: "/nonexistent/moost-spec/settings.json", isDirectory: false)
        ).load()
        XCTAssertEqual(settings, Settings())
    }

    func test_settings_save_round_trip_keeps_schema_version() throws {
        let dir = try makeTempDir("settings")
        let store = SettingsStore(file: dir.appendingPathComponent("settings.json"))
        var settings = Settings()
        settings.terminalApp = "iTerm2"
        settings.recentSessionLimit = 5
        settings.claudePath = "/usr/local/bin/claude"
        settings.summaryRallyCount = 2
        settings.copyAnimation = false
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
        XCTAssertEqual(try jsonDict(dir.appendingPathComponent("settings.json"))["schemaVersion"] as? Int, 1)
    }

    func test_settings_round_trip_preserves_pi_provider_and_model() throws {
        // Dart の settings_store.dart は piProvider / piModel を保存する（Issue #68）。
        // 型式は schemaVersion のみ必須のため、追加キーは保存・再読込で失われてはならない。
        let dir = try makeTempDir("settings-pi")
        let store = SettingsStore(file: dir.appendingPathComponent("settings.json"))
        var settings = Settings()
        settings.piProvider = "dspark"
        settings.piModel = "deepseek-v4-flash-0731"
        try store.save(settings)
        let loaded = try store.load()
        XCTAssertEqual(loaded.piProvider, "dspark")
        XCTAssertEqual(loaded.piModel, "deepseek-v4-flash-0731")
        // 未設定（空）のまま保存してもキーは付く（Dart と同じ書き出し）
        settings.piProvider = ""
        settings.piModel = ""
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
    }

    // MARK: projects.json（D1-D3）

    func test_projects_permissive_load_and_derived_display_name() throws {
        let dir = try makeTempDir("projects")
        let file = dir.appendingPathComponent("projects.json")
        let payload: [String: Any] = ["schemaVersion": 1, "projects": [
            ["id": "P1", "projectPath": "/work/alpha-service", "createdAt": "2026-09-01T00:00:00.000Z"],
            ["id": "P2"],                                     // projectPath 欠落 → skip
            ["id": 3, "projectPath": "/ng", "createdAt": "bad"], // 型違い → skip
        ]]
        let data = try MoostJSON.serialize(payload).data(using: .utf8)!
        try data.write(to: file, options: .atomic)
        let projects = try ProjectStore(file: file).load()
        XCTAssertEqual(projects.count, 1) // 1 件壊れで全体を捨てない（D3）
        XCTAssertEqual(projects[0].projectPath, "/work/alpha-service")
        XCTAssertEqual(projects[0].displayName, "alpha-service") // 非保存・path から導出し（D2）
    }

    // MARK: claude history.jsonl（E1-E5, F1）

    private func claudeReader() -> SessionHistoryReader {
        SessionHistoryReader(historyFile: fixtureURL("history.jsonl"),
                             agentId: "claude-code", excludeMarker: "#MOOST-FORK#")
    }

    func test_history_skips_broken_and_blank_lines_keeps_latest_per_session() throws {
        let sessions = try claudeReader().recentSessions(limit: 20)
        XCTAssertEqual(Set(sessions.map(\.sessionId)), Set(["S1", "S2", "S3"]))
        guard let s1 = sessions.first(where: { $0.sessionId == "S1" }),
              let s3 = sessions.first(where: { $0.sessionId == "S3" }) else {
            XCTFail("S1/S3 missing"); return
        }
        XCTAssertEqual(s1.agentId, "claude-code")
        XCTAssertEqual(s1.projectPath, "/work/alpha")
        XCTAssertEqual(s1.lastPrompt, "second prompt")     // 1 件目 1000 でなく最新 2000
        XCTAssertEqual(s1.updatedAt.ms, 2000)
        XCTAssertEqual(s3.lastPrompt, "third prompt")
        XCTAssertEqual(s3.updatedAt.ms, 4000)
        XCTAssertEqual(sessions.first?.sessionId, "S3")   // 降順（E5）
    }

    func test_fork_exclusion_is_line_level_not_session_level() throws {
        let sessions = try claudeReader().recentSessions(limit: 20)
        XCTAssertFalse(sessions.map(\.sessionId).contains("S4")) // 全行マーカー → 除外
        guard let s2 = sessions.first(where: { $0.sessionId == "S2" }) else {
            XCTFail("mixed S2 must remain"); return
        }
        XCTAssertEqual(s2.lastPrompt, "normal prompt")    // マーカー行のみ除外（E3）
        XCTAssertEqual(s2.updatedAt.ms, 1500)
    }

    func test_display_title_fallbacks() throws {
        let sessions = try claudeReader().recentSessions(limit: 20)
        let s1 = sessions.first(where: { $0.sessionId == "S1" })!
        XCTAssertNil(s1.aiTitle)
        XCTAssertEqual(s1.displayTitle, "second prompt")  // F1: ai-title 無は最終プロンプト
        let long = RecentSession(agentId: "claude-code", sessionId: "L", projectPath: "/w",
                                lastPrompt: String(repeating: "あ", count: 60),
                                updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Array(long.displayTitle).count, 50) // F3: 50 字截り（grapheme 単位）
        let titled = s1.withAiTitle("AI 表題")
        XCTAssertEqual(titled.displayTitle, "AI 表題")     // F2: ai-title 優先
    }

    // MARK: codex history.jsonl（E6-E7）

    func test_codex_history_aggregates_seconds_to_millis_and_excludes_forks() throws {
        let entries = try CodexHistoryReader(historyFile: fixtureURL("codex_history.jsonl"),
                                             excludeMarker: "#MOOST-FORK#").aggregatedEntries()
        XCTAssertEqual(entries.map(\.sessionId), ["CS1", "CS2"]) // CS3 は全行マーカー → 除外
        XCTAssertEqual(entries[0].lastPrompt, "second prompt")
        XCTAssertEqual(entries[0].updatedAt.ms, 200_000) // 秒→ms（E7）
        XCTAssertEqual(entries[1].lastPrompt, "normal prompt")
        XCTAssertEqual(entries[1].updatedAt.ms, 150_000)
    }

    // MARK: ai-title（F2）

    func test_ai_title_reads_latest_from_tail() throws {
        let reader = AiTitleReader(
            projectsDirectory: fixtureURL("claude_projects"))
        XCTAssertEqual(try reader.latestAiTitle("0f0f0f0f-1111-2222-3333-444455556666"),
                       "新しい表題") // 逆順で最初＝最新。「古い表題」ではない
        XCTAssertNil(try reader.latestAiTitle("deadbeef-0000-0000-0000-000000000000"))
    }

    // MARK: resume command（G1）

    func test_shell_escape_quotes_dangerous_payloads() {
        XCTAssertEqual(shellEscape("echo hi"), "'echo hi'")
        XCTAssertEqual(shellEscape("it's"), "'it'\\''s'")
        let command = "cd \(shellEscape("/work/a b")) && echo \(shellEscape("echo $(whoami) | tee x"))"
        XCTAssertTrue(command.hasPrefix("cd '/work/a b' &&"))
        XCTAssertTrue(command.contains("'echo $(whoami) | tee x'")) // 一重クォートで文字列化
    }

    // MARK: v1 → v2 初回移行

    func test_first_launch_migrates_v1_to_v2_once() throws {
        let home = try makeTempDir("home")
        let moost = home.appendingPathComponent(".moost")
        let v1 = moost.appendingPathComponent("v1")
        try FileManager.default.createDirectory(at: v1, withIntermediateDirectories: true)
        try "v1-bytes".data(using: .utf8)!.write(to: v1.appendingPathComponent("memos.json"), options: .atomic)
        try "settings".data(using: .utf8)!.write(to: v1.appendingPathComponent("settings.json"), options: .atomic)
        XCTAssertTrue(try DataMigration.migrateIfNeeded(homeDirectoryPath: home.path))
        let v2 = moost.appendingPathComponent("v2")
        XCTAssertEqual(try String(contentsOf: v2.appendingPathComponent("memos.json"), encoding: .utf8), "v1-bytes")
        XCTAssertFalse(try DataMigration.migrateIfNeeded(homeDirectoryPath: home.path)) // 2 回目 no-op
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: v2.appendingPathComponent(".migrated-from-v1").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: v1.appendingPathComponent("memos.json").path)) // v1 は読み取り専用で残る（復旧可）
    }

    func test_migration_from_empty_home_just_creates_v2() throws {
        let home = try makeTempDir("home-empty")
        XCTAssertFalse(try DataMigration.migrateIfNeeded(homeDirectoryPath: home.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".moost/v2").path))
    }
}
