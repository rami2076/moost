#if canImport(SQLite3)
import XCTest
import SQLite3
@testable import MoostCore

/// Hermes（state.db）リーダー・要約エクストラクタのテスト。
/// DHBW の実 DB（v0.22.3）と同じスキーマのフィクスチャを一時 DB で作る。
final class HermesSessionReaderTests: XCTestCase {

    // MARK: - フィクスチャヘルパー

    /// 一時ディレクトリに state.db を作り、URL を返す（メソッド終了時に削除する）。
    private func makeTempStateDB(
        file: StaticString = #filePath,
        line: UInt = #line,
        statements: [String]
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost-hermes-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("state.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK, file: file, line: line)
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK,
                           "sql: \(sql)", file: file, line: line)
        }
        sqlite3_close(handle)
        return dbURL
    }

    private func insertSession(
        id: String, source: String = "local", title: String = "", cwd: String = "",
        startedAt: Double = 100, lastActivityAt: Double? = nil,
        messageCount: Int = 1, archived: Int = 0, hidden: Int = 0
    ) -> String {
        var cols = "id, source, title, cwd, started_at, message_count, archived, hidden"
        var vals = "'\(id)', '\(source)', '\(title)', '\(cwd)', \(startedAt), \(messageCount), \(archived), \(hidden)"
        if let last = lastActivityAt {
            cols += ", last_activity_at"
            vals += ", \(last)"
        }
        return "INSERT INTO sessions (\(cols)) VALUES (\(vals));"
    }

    private func insertMessage(
        sessionId: String, role: String, content: String = "",
        toolName: String = "", timestamp: Double = 0
    ) -> String {
        "INSERT INTO messages (session_id, role, content, tool_name, timestamp) "
            + "VALUES ('\(sessionId)', '\(role)', '\(content)', '\(toolName)', \(timestamp));"
    }

    private func createSchema() -> [String] {
        [
            """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                source TEXT DEFAULT 'local',
                title TEXT,
                cwd TEXT,
                started_at REAL,
                last_activity_at REAL,
                message_count INTEGER DEFAULT 0,
                archived INTEGER DEFAULT 0,
                hidden INTEGER DEFAULT 0
            );
            """,
            """
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                role TEXT,
                content TEXT,
                tool_name TEXT,
                timestamp REAL,
                active INTEGER DEFAULT 1
            );
            """,
        ]
    }

    // MARK: - HermesSessionReader

    func test_reader_lists_cli_sessions_newest_first_with_title_and_last_prompt() throws {
        let dbURL = try makeTempStateDB(statements: createSchema() + [
            insertSession(id: "local-a", title: "表題A", cwd: "/w1",
                          startedAt: 100, lastActivityAt: 200, messageCount: 2),
            insertSession(id: "oneshot-b", source: "oneshot", title: "表題B", cwd: "/w2",
                          startedAt: 300, lastActivityAt: nil, messageCount: 1),
            // 除外系: acp / gateway / 起動スタブ / アーカイブ / 非表示
            insertSession(id: "acp-c", source: "acp", messageCount: 5),
            insertSession(id: "gw-d", source: "telegram", messageCount: 5),
            insertSession(id: "stub-e", source: "local", messageCount: 0),
            insertSession(id: "arch-f", source: "local", messageCount: 3, archived: 1),
            insertSession(id: "hid-g", source: "local", messageCount: 3, hidden: 1),
            insertMessage(sessionId: "local-a", role: "user", content: "こんにちは", timestamp: 150),
            insertMessage(sessionId: "local-a", role: "assistant", content: "はい", timestamp: 160),
            insertMessage(sessionId: "oneshot-b", role: "user", content: "test", timestamp: 250),
        ])

        let entries = try HermesSessionReader(dbURL: dbURL).recentSessions(limit: 20)
        XCTAssertEqual(entries.map(\.sessionId), ["oneshot-b", "local-a"])
        XCTAssertEqual(entries[0].projectPath, "/w2")
        XCTAssertEqual(entries[0].lastPrompt, "test")
        XCTAssertEqual(entries[0].aiTitle, "表題B")
        let a = entries[1]
        XCTAssertEqual(a.projectPath, "/w1")
        XCTAssertEqual(a.lastPrompt, "こんにちは")
        XCTAssertEqual(a.aiTitle, "表題A")
        XCTAssertEqual(a.updatedAt.timeIntervalSince1970, 200, accuracy: 0.001)
        XCTAssertEqual(entries[0].updatedAt.timeIntervalSince1970, 300, accuracy: 0.001)
    }

    func test_reader_missing_db_is_empty() throws {
        let url = URL(fileURLWithPath: "/nonexistent/hermes/state.db")
        let entries = try HermesSessionReader(dbURL: url).recentSessions()
        XCTAssertTrue(entries.isEmpty)
    }

    func test_reader_takes_limit() throws {
        let dbURL = try makeTempStateDB(statements: createSchema() + [
            insertSession(id: "s1", startedAt: 100, messageCount: 1),
            insertSession(id: "s2", startedAt: 200, messageCount: 1),
        ])
        let entries = try HermesSessionReader(dbURL: dbURL).recentSessions(limit: 1)
        XCTAssertEqual(entries.map(\.sessionId), ["s2"])
    }

    func test_reader_corrupted_db_throws() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost-hermes-corrupt-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("state.db")
        try Data("not a sqlite database".utf8).write(to: dbURL)
        XCTAssertThrowsError(try HermesSessionReader(dbURL: dbURL).recentSessions())
    }

    // MARK: - HermesTranscriptExtractor

    func test_extractor_recent_keeps_last_rally_including_tool_output() throws {
        let dbURL = try makeTempStateDB(statements: createSchema() + [
            insertSession(id: "local-a", startedAt: 100, messageCount: 4),
            insertMessage(sessionId: "local-a", role: "user", content: "first", timestamp: 1),
            insertMessage(sessionId: "local-a", role: "assistant", content: "answer1", timestamp: 2),
            insertMessage(sessionId: "local-a", role: "user", content: "second", timestamp: 3),
            insertMessage(sessionId: "local-a", role: "assistant", content: "", timestamp: 4),
            insertMessage(sessionId: "local-a", role: "tool",
                          content: #"{"output": "ls output", "exit_code": 0}"#, toolName: "terminal", timestamp: 5),
            insertMessage(sessionId: "local-a", role: "assistant", content: "answer2", timestamp: 6),
        ])

        let extractor = HermesTranscriptExtractor(dbURL: dbURL)
        let text = extractor.extract(sessionId: "local-a", full: false, rallies: 1)
        XCTAssertTrue(text.contains("User: second"))
        XCTAssertFalse(text.contains("User: first"))
        XCTAssertTrue(text.contains("Assistant: answer2"))
        // 空の assistant 行はスキップされる
        XCTAssertFalse(text.contains("Assistant: \n"))
        XCTAssertTrue(text.contains("Tool(terminal): ls output"))
    }

    func test_extractor_full_returns_everything_and_skips_unknown_role() throws {
        let dbURL = try makeTempStateDB(statements: createSchema() + [
            insertSession(id: "local-a", startedAt: 100, messageCount: 3),
            insertMessage(sessionId: "local-a", role: "user", content: "first", timestamp: 1),
            insertMessage(sessionId: "local-a", role: "assistant", content: "answer1", timestamp: 2),
            insertMessage(sessionId: "local-a", role: "reasoning", content: "skip me", timestamp: 3),
            insertMessage(sessionId: "local-a", role: "user", content: "second", timestamp: 4),
            insertMessage(sessionId: "local-a", role: "assistant", content: "answer2", timestamp: 5),
        ])

        let extractor = HermesTranscriptExtractor(dbURL: dbURL)
        let text = extractor.extract(sessionId: "local-a", full: true, rallies: 1)
        XCTAssertTrue(text.contains("User: first"))
        XCTAssertTrue(text.contains("User: second"))
        XCTAssertTrue(text.contains("Assistant: answer1"))
        XCTAssertTrue(text.contains("Assistant: answer2"))
        XCTAssertFalse(text.contains("skip me"))
    }

    func test_extractor_missing_session_or_db_is_empty() throws {
        let dbURL = try makeTempStateDB(statements: createSchema())
        let extractor = HermesTranscriptExtractor(dbURL: dbURL)
        XCTAssertEqual(extractor.extract(sessionId: "nope", full: true), "")
        let missing = HermesTranscriptExtractor(
            dbURL: URL(fileURLWithPath: "/nonexistent/hermes/state.db"))
        XCTAssertEqual(missing.extract(sessionId: "nope", full: true), "")
    }

    // MARK: - SessionSummarizer 経由（hermes は CLI 不要で抽出をそのまま返す）

    func test_session_summarizer_returns_transcript_for_hermes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost-hermes-home-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".hermes", isDirectory: true),
            withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent(".hermes/state.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        for sql in createSchema() + [
            insertSession(id: "local-a", title: "T", cwd: "/w", startedAt: 100, messageCount: 2),
            insertMessage(sessionId: "local-a", role: "user", content: "質問", timestamp: 1),
            insertMessage(sessionId: "local-a", role: "assistant", content: "回答", timestamp: 2),
        ] {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        }
        sqlite3_close(handle)

        let summarizer = SessionSummarizer(home: dir.path)
        let session = RecentSession(agentId: ResumeCommand.hermesAgentId,
                                    sessionId: "local-a",
                                    projectPath: "/w",
                                    lastPrompt: "質問",
                                    updatedAt: Date(timeIntervalSince1970: 200))
        let text = try await summarizer.summarize(session: session, scope: .recent)
        XCTAssertTrue(text.contains("User: 質問"))
        XCTAssertTrue(text.contains("Assistant: 回答"))
    }

    func test_session_summarizer_hermes_missing_session_throws() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost-hermes-home2-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".hermes", isDirectory: true),
            withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent(".hermes/state.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        for sql in createSchema() { XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK) }
        sqlite3_close(handle)

        let summarizer = SessionSummarizer(home: dir.path)
        let session = RecentSession(agentId: ResumeCommand.hermesAgentId,
                                    sessionId: "missing",
                                    projectPath: "",
                                    lastPrompt: "",
                                    updatedAt: Date())
        do {
            _ = try await summarizer.summarize(session: session, scope: .recent)
            XCTFail("should throw")
        } catch let error as SummarizeError {
            XCTAssertEqual(error.message, "no transcript found for the session")
        }
    }
}
#endif
