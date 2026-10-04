import XCTest
@testable import MoostCore

/// 要約実行（サブプロセス）のテスト。フェイクの claude / codex 実行ファイル
/// （シェルスクリプト）でプロセス処理を検証する。実際の CLI は呼ばない。
/// リファレンス: claude_summarizer_test.dart / codex_summarizer_test.dart。
final class SummarizerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_summarizer_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// フェイクの実行ファイル（シェルスクリプト）を作ってパスを返す。
    private func writeFakeExecutable(named name: String, script: String) throws -> String {
        let file = tempDir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + script + "\n").write(
            to: file, atomically: true, encoding: String.Encoding.utf8)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", file.path]
        try chmod.run()
        chmod.waitUntilExit()
        return file.path
    }

    // MARK: - ClaudeSummarizer

    func test_claude_strips_internal_env_vars_from_child_process() async throws {
        // 実際のプロセス環境に依存すると CI では汚染されておらず、
        // フィルタが効いたことにならず偽陽性でパスしてしまう。
        // 汚染された偽の環境を明示的に注入し、決定論的に検証する。
        let pollutedEnv = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "CLAUDE_CODE_CHILD_SESSION": "1",
            "CLAUDE_PID": "999",
            "HARMLESS_VAR": "keep-me",
        ]

        // env をそのままダンプするフェイク: 直接起動すると汚染変数が渡って
        // しまうことをまず確認する（対策の効果を測る基準）
        let path = try writeFakeExecutable(named: "claude", script: "env")
        let direct = Process()
        direct.executableURL = URL(fileURLWithPath: path)
        direct.environment = pollutedEnv
        // includeParentEnvironment = false 相当にするために environment を上書きする
        // （デフォルトでは親の環境とマージされるため、ダミーでも含まれる）
        direct.standardOutput = Pipe()
        try direct.run()
        let directOut = direct.standardOutput as! Pipe
        let directData = directOut.fileHandleForReading.readDataToEndOfFile()
        direct.waitUntilExit()
        let directStdout = String(data: directData, encoding: .utf8) ?? ""
        XCTAssertTrue(directStdout.contains("CLAUDE_CODE_CHILD_SESSION"))

        let summarizer = ClaudeSummarizer(claudePath: path, environment: pollutedEnv)
        let output = try await summarizer.summarizeTranscript(
            "x", workingDirectory: tempDir.path)
        XCTAssertFalse(output.contains("CLAUDE_CODE_CHILD_SESSION"))
        XCTAssertFalse(output.contains("CLAUDE_PID"))
        XCTAssertTrue(output.contains("HARMLESS_VAR"))
    }

    func test_claude_passes_stdin_and_returns_stdout() async throws {
        let path = try writeFakeExecutable(named: "claude", script: "cat -")
        let summarizer = ClaudeSummarizer(claudePath: path)
        let result = try await summarizer.summarizeTranscript(
            "User: hello\nAssistant: world", workingDirectory: tempDir.path)
        XCTAssertEqual(result, "User: hello\nAssistant: world")
    }

    func test_claude_large_output_does_not_deadlock_pipe_buffer() async throws {
        let path = try writeFakeExecutable(
            named: "claude",
            script: "i=0; while [ $i -lt 3000 ]; do "
                + "echo \"0123456789012345678901234567890123456789\"; i=$((i+1)); done")
        let summarizer = ClaudeSummarizer(claudePath: path)
        let result = try await summarizer.summarizeTranscript(
            "x", workingDirectory: tempDir.path)
        XCTAssertGreaterThan(result.count, 64 * 1024)
    }

    func test_claude_summary_prompt_starts_with_moost_marker() async throws {
        let path = try writeFakeExecutable(named: "claude", script: "echo \"$@\"")
        let summarizer = ClaudeSummarizer(claudePath: path)
        let result = try await summarizer.summarizeFullSession(
            sessionId: "abc", workingDirectory: tempDir.path)
        XCTAssertTrue(result.contains(ClaudeSummarizer.marker))
        XCTAssertTrue(result.contains("--resume abc"))
        XCTAssertTrue(result.contains("--fork-session"))
        XCTAssertTrue(result.contains("--model haiku"))
    }

    func test_claude_non_zero_exit_throws_with_stderr() async throws {
        let path = try writeFakeExecutable(named: "claude", script: "echo \"boom\" >&2; exit 7")
        let summarizer = ClaudeSummarizer(claudePath: path)
        do {
            _ = try await summarizer.summarizeTranscript("x", workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("boom"))
        }
    }

    func test_claude_broken_pipe_when_process_exits_early_is_handled() async throws {
        // stdin を読まずに即終了するプロセス → broken pipe を握りつぶして
        // exitCode ベースのエラーになることを検証
        let path = try writeFakeExecutable(named: "claude", script: "exit 3")
        let summarizer = ClaudeSummarizer(claudePath: path)
        do {
            _ = try await summarizer.summarizeTranscript(
                String(repeating: "x", count: 256 * 1024), workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("3"))
        }
    }

    func test_claude_missing_executable_throws() async throws {
        let summarizer = ClaudeSummarizer(
            claudePath: tempDir.appendingPathComponent("no-such-claude").path)
        do {
            _ = try await summarizer.summarizeTranscript("x", workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("failed to start claude"))
        }
    }

    // MARK: - CodexSummarizer

    /// `--output-last-message` の次の引数を `$out` に入れた状態で script を
    /// 実行するフェイク codex を作る。
    private func writeFakeCodex(_ script: String) throws -> String {
        try writeFakeExecutable(named: "codex", script: """
        out=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "--output-last-message" ]; then out="$a"; fi
          prev="$a"
        done
        \(script)
        """)
    }

    func test_codex_passes_stdin_and_reads_output_file() async throws {
        let path = try writeFakeCodex("cat - > \"$out\"")
        let summarizer = CodexSummarizer(codexPath: path)
        let result = try await summarizer.summarizeTranscript(
            "User: hello\nAssistant: world", workingDirectory: tempDir.path)
        XCTAssertEqual(result, "User: hello\nAssistant: world")
    }

    func test_codex_transcript_summary_runs_ephemeral_exec_with_marker() async throws {
        let path = try writeFakeCodex("echo \"$@\" > \"$out\"")
        let summarizer = CodexSummarizer(codexPath: path)
        let result = try await summarizer.summarizeTranscript(
            "x", workingDirectory: tempDir.path)
        XCTAssertTrue(result.hasPrefix("exec "))
        XCTAssertTrue(result.contains("--ephemeral"))
        XCTAssertTrue(result.contains("--skip-git-repo-check"))
        XCTAssertTrue(result.contains("--sandbox read-only"))
        XCTAssertTrue(result.contains(CodexSummarizer.marker))
    }

    func test_codex_full_summary_resumes_session_ephemerally() async throws {
        let path = try writeFakeCodex("echo \"$@\" > \"$out\"")
        let summarizer = CodexSummarizer(codexPath: path)
        let result = try await summarizer.summarizeFullSession(
            sessionId: "abc", workingDirectory: tempDir.path)
        XCTAssertTrue(result.hasPrefix("exec resume abc"))
        XCTAssertTrue(result.contains("--ephemeral"))
        XCTAssertTrue(result.contains(CodexSummarizer.marker))
    }

    func test_codex_non_zero_exit_throws_with_stderr() async throws {
        let path = try writeFakeCodex("echo \"boom\" >&2; exit 7")
        let summarizer = CodexSummarizer(codexPath: path)
        do {
            _ = try await summarizer.summarizeTranscript("x", workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("boom"))
        }
    }

    func test_codex_missing_output_file_throws() async throws {
        // 正常終了したのに結果ファイルを書かないフェイク
        let path = try writeFakeCodex("exit 0")
        let summarizer = CodexSummarizer(codexPath: path)
        do {
            _ = try await summarizer.summarizeTranscript("x", workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("did not produce"))
        }
    }

    func test_codex_missing_executable_throws() async throws {
        let summarizer = CodexSummarizer(
            codexPath: tempDir.appendingPathComponent("no-such-codex").path)
        do {
            _ = try await summarizer.summarizeTranscript("x", workingDirectory: tempDir.path)
            XCTFail("expected SummarizeError")
        } catch let error as SummarizeError {
            XCTAssertTrue(error.message.contains("failed to start codex"))
        }
    }
}
