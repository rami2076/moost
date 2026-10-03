import XCTest
@testable import MoostCore

/// 要約用 transcript 抽出のテスト。
/// リファレンス: transcript_extractor_test.dart / codex_transcript_extractor_test.dart
/// / pi_adapter_test.dart（PiTranscriptExtractor の group）。
final class TranscriptExtractorTests: XCTestCase {
    private var tempDir: URL!
    private var projectsDir: URL!
    private var sessionsDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_extract_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        projectsDir = tempDir.appendingPathComponent("projects", isDirectory: true)
        sessionsDir = tempDir.appendingPathComponent("sessions", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: String.Encoding.utf8)
    }

    // MARK: - Claude

    private func claudeUserLine(_ text: String, sidechain: Bool = false) -> String {
        #if swift(>=5.9)
        // JSON 組み立ては手書きの辞書より文字列の方が軽い。ここは fixture 用。
        #endif
        return "{\"type\":\"user\",\"isSidechain\":\(sidechain ? "true" : "false"),"
            + "\"message\":{\"role\":\"user\",\"content\":\"\(text)\"}}"
    }

    private func claudeAssistantLine(_ text: String) -> String {
        "{\"type\":\"assistant\",\"isSidechain\":false,\"message\":{\"role\":\"assistant\","
            + "\"content\":[{\"type\":\"text\",\"text\":\"\(text)\"}]}}"
    }

    private func writeClaudeSession(_ lines: [String]) throws {
        try write(lines.joined(separator: "\n"),
                  to: projectsDir.appendingPathComponent("-Users-u-proj/abc-session.jsonl"))
    }

    func test_claude_returns_null_when_session_file_missing() throws {
        let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
        XCTAssertNil(try extractor.extract(sessionId: "abc-session"))
    }

    func test_claude_extracts_last_n_rallies() throws {
        try writeClaudeSession([
            claudeUserLine("question 1"), claudeAssistantLine("answer 1"),
            claudeUserLine("question 2"), claudeAssistantLine("answer 2"),
            claudeUserLine("question 3"), claudeAssistantLine("answer 3"),
        ])
        let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
        let transcript = try XCTUnwrap(extractor.extract(sessionId: "abc-session", rallies: 2))
        XCTAssertFalse(transcript.contains("question 1"))
        XCTAssertTrue(transcript.contains("User: question 2"))
        XCTAssertTrue(transcript.contains("Assistant: answer 2"))
        XCTAssertTrue(transcript.contains("User: question 3"))
        XCTAssertTrue(transcript.contains("Assistant: answer 3"))
    }

    func test_claude_skips_sidechain_and_non_message_lines() throws {
        try writeClaudeSession([
            "{\"type\":\"file-history-snapshot\",\"snapshot\":{}}",
            "broken line",
            claudeUserLine("sidechain q", sidechain: true),
            claudeUserLine("real question"),
            claudeAssistantLine("real answer"),
        ])
        let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
        let transcript = try XCTUnwrap(extractor.extract(sessionId: "abc-session", rallies: 5))
        XCTAssertFalse(transcript.contains("sidechain q"))
        XCTAssertTrue(transcript.contains("User: real question"))
        XCTAssertTrue(transcript.contains("Assistant: real answer"))
    }

    func test_claude_joins_multiple_assistant_blocks_in_one_rally() throws {
        try writeClaudeSession([
            claudeUserLine("q"),
            claudeAssistantLine("part 1"),
            claudeAssistantLine("part 2"),
        ])
        let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
        let transcript = try XCTUnwrap(extractor.extract(sessionId: "abc-session", rallies: 1))
        XCTAssertTrue(transcript.contains("Assistant: part 1"))
        XCTAssertTrue(transcript.contains("Assistant: part 2"))
    }

    func test_claude_returns_null_when_no_rallies() throws {
        try writeClaudeSession(["{\"type\":\"noise\"}"])
        let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
        XCTAssertNil(try extractor.extract(sessionId: "abc-session"))
    }

    // MARK: - Codex

    private let uuid = "019dd8a1-a10c-7ef0-867e-3873d724ec84"

    private func codexUserLine(_ text: String) -> String {
        "{\"timestamp\":\"t\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\","
            + "\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"\(text)\"}]}}"
    }

    private func codexAssistantLine(_ text: String) -> String {
        "{\"timestamp\":\"t\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\","
            + "\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(text)\"}]}}"
    }

    private func writeRollout(_ lines: [String]) throws {
        try write(lines.joined(separator: "\n"),
                  to: sessionsDir.appendingPathComponent(
                      "2026/04/29/rollout-2026-04-29T18-46-04-\(uuid).jsonl"))
    }

    private func makeExtractor() -> CodexTranscriptExtractor {
        CodexTranscriptExtractor(rolloutReader: CodexRolloutReader(sessionsDir: sessionsDir))
    }

    func test_codex_returns_null_when_rollout_missing() throws {
        XCTAssertNil(try makeExtractor().extract(sessionId: uuid))
    }

    func test_codex_extracts_last_rally_by_default() throws {
        try writeRollout([
            codexUserLine("first question"), codexAssistantLine("first answer"),
            codexUserLine("second question"), codexAssistantLine("second answer"),
        ])
        let transcript = try XCTUnwrap(makeExtractor().extract(sessionId: uuid))
        XCTAssertEqual(transcript, "User: second question\nAssistant: second answer")
    }

    func test_codex_extracts_multiple_rallies_in_order() throws {
        try writeRollout([
            codexUserLine("q1"), codexAssistantLine("a1"),
            codexUserLine("q2"), codexAssistantLine("a2"),
        ])
        let transcript = try XCTUnwrap(makeExtractor().extract(sessionId: uuid, rallies: 2))
        XCTAssertEqual(transcript, "User: q1\nAssistant: a1\n\nUser: q2\nAssistant: a2")
    }

    func test_codex_skips_system_context_user_messages() throws {
        try writeRollout([
            codexUserLine("<environment_context>cwd: /p</environment_context>"),
            codexUserLine("<user_instructions>rules</user_instructions>"),
            codexUserLine("real question"),
            codexAssistantLine("answer"),
        ])
        let transcript = try XCTUnwrap(makeExtractor().extract(sessionId: uuid, rallies: 5))
        XCTAssertEqual(transcript, "User: real question\nAssistant: answer")
    }

    func test_codex_ignores_event_msg_and_non_message_lines() throws {
        try writeRollout([
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"message\":\"x\"}}",
            "broken line",
            codexUserLine("q"),
            codexAssistantLine("a"),
        ])
        let transcript = try XCTUnwrap(makeExtractor().extract(sessionId: uuid))
        XCTAssertEqual(transcript, "User: q\nAssistant: a")
    }

    // MARK: - pi

    private func writePiSession(sessionId: String, userText: String) throws {
        let sessionLine = "{\"type\":\"session\",\"version\":2,\"id\":\"\(sessionId)\","
            + "\"timestamp\":\"2026-03-01T00:00:00.000Z\",\"cwd\":\"/work/moost\"}"
        let userLine = "{\"type\":\"message\",\"id\":\"m1\",\"parentId\":null,"
            + "\"timestamp\":\"2026-03-01T00:00:01.000Z\",\"message\":{\"role\":\"user\","
            + "\"content\":[{\"type\":\"text\",\"text\":\"\(userText)\"}]}}"
        let assistantLine = "{\"type\":\"message\",\"id\":\"m2\",\"parentId\":\"m1\","
            + "\"timestamp\":\"2026-03-01T00:00:02.000Z\",\"message\":{\"role\":\"assistant\","
            + "\"content\":[{\"type\":\"thinking\",\"thinking\":\"hmm\"},"
            + "{\"type\":\"text\",\"text\":\"了解です\"}]}}"
        try write([sessionLine, userLine, assistantLine].joined(separator: "\n"),
                  to: sessionsDir.appendingPathComponent(
                      "2026-03-01T00-00-00_\(sessionId).jsonl"))
    }

    func test_pi_extracts_recent_messages_as_user_assistant_text() throws {
        try writePiSession(sessionId: "sess-extract", userText: "最初の質問")
        let extractor = PiTranscriptExtractor(sessionsDir: sessionsDir)
        let text = extractor.extract(sessionId: "sess-extract")
        XCTAssertTrue(text.contains("User: 最初の質問"))
        XCTAssertTrue(text.contains("Assistant: 了解です"))
    }

    func test_pi_full_scope_includes_messages() throws {
        try writePiSession(sessionId: "sess-full", userText: "A")
        let extractor = PiTranscriptExtractor(sessionsDir: sessionsDir)
        let text = extractor.extract(sessionId: "sess-full", full: true)
        XCTAssertTrue(text.contains("Assistant: 了解です"))
    }

    func test_pi_empty_result_when_session_file_missing() throws {
        let extractor = PiTranscriptExtractor(sessionsDir: sessionsDir)
        XCTAssertEqual(extractor.extract(sessionId: "no-such"), "")
    }
}
