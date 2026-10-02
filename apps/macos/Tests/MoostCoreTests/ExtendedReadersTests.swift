import XCTest
@testable import MoostCore

/// pi・codex・統合（SessionAggregator）の読み取りテスト。
/// リファレンス assertion は packages/core/test/pi_adapter_test.dart と
/// codex_adapter_test.dart を写している。Fixture は合成（実データ依存にしない）。

final class ExtendedReadersTests: XCTestCase {

    // MARK: - helpers

    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost-" + label + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    private func makePiSessionFile(dir: URL, cwdDir: String, name: String,
                                   header: String, lines: [String]) throws -> URL {
        let file = dir.appendingPathComponent(cwdDir).appendingPathComponent(name)
        try write(header + "\n" + lines.joined(separator: "\n") + "\n", to: file)
        return file
    }

    // MARK: - pi sessions

    func test_pi_reader_extracts_header_and_last_user_text() throws {
        let root = try makeTempDir("pi-reader")
        defer { try? FileManager.default.removeItem(at: root) }

        let header = "{\"type\":\"session\",\"version\":3,\"id\":\"01a08150-ffc2-748c-bbd9-2c5f598dd2f0\","
            + "\"timestamp\":\"2026-09-08T13:59:24.355Z\",\"cwd\":\"/Users/foo/project\"}"
        let lines = [
            "{\"type\":\"message\",\"id\":\"m1\",\"parentId\":\"p\","
                + "\"timestamp\":\"2026-09-08T14:00:23.541Z\","
                + "\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"助けて\"}]}}",
            "{\"type\":\"message\",\"id\":\"m2\",\"parentId\":\"p\","
                + "\"timestamp\":\"2026-09-08T14:01:00.000Z\","
                + "\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hello pi\"}]}}",
            "{\"type\":\"message\",\"id\":\"m3\",\"parentId\":\"p\","
                + "\"timestamp\":\"2026-09-08T14:02:00.000Z\","
                + "\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}}",
        ]
        try makePiSessionFile(dir: root, cwdDir: "--Users-foo-project--",
                              name: "2026-09-08T13-59-24-355Z_01a08150.jsonl",
                              header: header, lines: lines)

        let entries = try PiSessionHistoryReader(sessionsDir: root).recentSessions()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sessionId, "01a08150-ffc2-748c-bbd9-2c5f598dd2f0")
        XCTAssertEqual(entries[0].projectPath, "/Users/foo/project")
        // 最後のユーザー発言（assistant は取らない）
        XCTAssertEqual(entries[0].lastPrompt, "hello pi")
        // 最新は末尾の assistant メッセージ時刻（ヘッダより新しい）
        XCTAssertEqual(entries[0].updatedAt,
                       ISOUTC.parse("2026-09-08T14:02:00.000Z"))
    }

    func test_pi_reader_sorts_newest_first_and_respects_limit() throws {
        let root = try makeTempDir("pi-sort")
        defer { try? FileManager.default.removeItem(at: root) }

        let older = "{\"type\":\"session\",\"version\":3,\"id\":\"old-id\","
            + "\"timestamp\":\"2026-09-08T13:00:00.000Z\",\"cwd\":\"/w\"}"
        let newer = "{\"type\":\"session\",\"version\":3,\"id\":\"new-id\","
            + "\"timestamp\":\"2026-09-09T13:00:00.000Z\",\"cwd\":\"/w2\"}"
        try makePiSessionFile(dir: root, cwdDir: "a", name: "1_old.jsonl",
                              header: older, lines: ["{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"一\"}]}}"])
        try makePiSessionFile(dir: root, cwdDir: "b", name: "2_new.jsonl",
                              header: newer, lines: [])

        let entries = try PiSessionHistoryReader(sessionsDir: root).recentSessions(limit: 1)
        XCTAssertEqual(entries.map(\.sessionId), ["new-id"])
    }

    func test_pi_reader_missing_dir_returns_empty() throws {
        let root = try makeTempDir("pi-missing") // 中身なし（sessions 自体が無い状態を再現）
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = try PiSessionHistoryReader(
            sessionsDir: root.appendingPathComponent("nope")).recentSessions()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - codex rollout

    func test_codex_rollout_scan_finds_by_suffix_and_latest_wins() throws {
        let root = try makeTempDir("codex-rollout")
        defer { try? FileManager.default.removeItem(at: root) }

        let sid = "01234567-89ab-cdef-0123-456789abcdef"
        try write("dummy", to: root.appendingPathComponent("2026/09/08/rollout-2026-09-08T10-00-00-\(sid).jsonl"))
        // 同日中の新しい rollout が残る
        try write("dummy2", to: root.appendingPathComponent("2026/09/08/rollout-2026-09-08T11-00-00-\(sid).jsonl"))
        // 対象外の名前
        try write("x", to: root.appendingPathComponent("2026/09/08/other-file.jsonl"))

        let index = try CodexRolloutReader(sessionsDir: root).scan()
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index[sid]?.lastPathComponent,
                       "rollout-2026-09-08T11-00-00-\(sid).jsonl")
    }

    func test_codex_rollout_reads_cwd_from_session_meta() throws {
        let root = try makeTempDir("codex-cwd")
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("rollout-1-01234567-89ab-cdef-0123-456789abcdef.jsonl")
        try write(
            "{\"timestamp\":\"2026-09-08T09:00:00.000Z\",\"type\":\"session_meta\","
                + "\"payload\":{\"cwd\":\"/work/a b\",\"id\":\"01234567-89ab-cdef-0123-456789abcdef\","
                + "\"timestamp\":\"2026-09-08T09:00:00.000Z\"}}",
            to: file)
        // 1 行目に無いときは先頭 10 行まで探す
        let file2 = root.appendingPathComponent("rollout-2-01234567-89ab-cdef-0123-456789abcdef.jsonl")
        try write("noise\n" + "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/x\"}}", to: file2)

        let reader = CodexRolloutReader(sessionsDir: root)
        XCTAssertEqual(try reader.readCwd(file), "/work/a b")
        XCTAssertEqual(try reader.readCwd(file2), "/x")
    }

    // MARK: - aggregator

    func test_aggregator_merges_agents_newest_first_and_takes_limit() throws {
        let root = try makeTempDir("aggregator")
        defer { try? FileManager.default.removeItem(at: root) }

        // claude: history 2 行（うち 1 行は要約マーカー除外）
        try write(
            "{\"display\":\"normal one\",\"timestamp\":3000,\"project\":\"/p1\",\"sessionId\":\"claude-1\"}\n"
                + "{\"display\":\"[Moost\u{8981}\u{7d04}] fork\",\"timestamp\":5000,\"project\":\"/p1\",\"sessionId\":\"claude-fork\"}\n",
            to: root.appendingPathComponent("claude.jsonl"))
        // codex: history 1 件 + rollout あり / もう 1 件は rollout なし（除外）。
        // session_id は rollout ファイル名の正規表現に合う UUID 形にする。
        let codexSid = "01234567-89ab-cdef-0123-456789abcdef"
        try write(
            "{\"session_id\":\"\(codexSid)\",\"ts\":9000,\"text\":\"codex prompt\"}\n"
                + "{\"session_id\":\"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\",\"ts\":8000,\"text\":\"no rollout\"}\n",
            to: root.appendingPathComponent("codex.jsonl"))
        try write(
            "{\"timestamp\":\"2026-09-08T09:00:00.000Z\",\"type\":\"session_meta\","
                + "\"payload\":{\"cwd\":\"/work/codex\"}}",
            to: root.appendingPathComponent("sessions/x/rollout-1-\(codexSid).jsonl"))
        // pi: 1 件（最新）
        try write(
            "{\"type\":\"session\",\"version\":3,\"id\":\"pi-1\",\"timestamp\":\"2026-09-10T03:04:05.000Z\",\"cwd\":\"/w/pi\"}\n"
                + "{\"type\":\"message\",\"timestamp\":\"2026-09-10T03:05:06.000Z\","
                + "\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"pi prompt\"}]}}",
            to: root.appendingPathComponent("pi/--Users--/x_pi-1.jsonl"))

        let merged = SessionAggregator.recentSessions(
            claudeHistoryFile: root.appendingPathComponent("claude.jsonl"),
            codexHistoryFile: root.appendingPathComponent("codex.jsonl"),
            codexSessionsDir: root.appendingPathComponent("sessions"),
            piSessionsDir: root.appendingPathComponent("pi"),
            limit: 3)
        XCTAssertEqual(merged.map(\.agentId), ["pi", "codex", "claude-code"])
        XCTAssertEqual(merged.map(\.sessionId), ["pi-1", codexSid, "claude-1"])
        XCTAssertEqual(merged[0].projectPath, "/w/pi")
        XCTAssertEqual(merged[1].projectPath, "/work/codex")
        XCTAssertEqual(merged[2].projectPath, "/p1")
    }

    func test_aggregator_missing_sources_yields_empty_but_not_fatal() {
        let merged = SessionAggregator.recentSessions(
            claudeHistoryFile: URL(fileURLWithPath: "/nonexistent/claude.jsonl"),
            codexHistoryFile: URL(fileURLWithPath: "/nonexistent/codex.jsonl"),
            codexSessionsDir: URL(fileURLWithPath: "/nonexistent/sessions"),
            piSessionsDir: URL(fileURLWithPath: "/nonexistent/pi"),
            limit: 5)
        XCTAssertTrue(merged.isEmpty)
    }
}
