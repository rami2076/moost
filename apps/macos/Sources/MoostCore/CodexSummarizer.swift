import Foundation

/// `codex exec` によるセッション要約の実行。
/// リファレンス実装: packages/core/lib/src/agent/codex/codex_summarizer.dart
///
/// - `--ephemeral` でセッションを永続化しない（rollout も history も残らず、
///   Claude の `--fork-session` に相当する分離になる）
/// - 念のためプロンプト先頭にマーカーを入れる（万一 history に記録される
///   モードで動いても一覧から除外できるように。design.md 5 章と同じ発想）
/// - codex exec の stdout は進捗ログを含むため、結果は
///   `--output-last-message` で書かせたファイルから読む
/// - サブプロセスの stdout/stderr は終了待ちの前に EOF まで読み切る
///   （パイプバッファ詰まりでデッドロックするため。design.md 7 章ハマりどころ 2）
public final class CodexSummarizer: Sendable {
    /// 要約実行の除外マーカー（ClaudeSummarizer.marker と同じ文字列）。
    public static let marker = "[Moost\u{8981}\u{7d04}]"

    /// 子プロセスが stdin を読まずに終了した場合、FileHandle.write は
    /// SIGPIPE でこのプロセスごと落ちる（ClaudeSummarizer と同じ対策）。
    private static func ignoreSIGPIPE() {
        #if canImport(Darwin)
        signal(SIGPIPE, SIG_IGN)
        #elseif canImport(Glibc)
        signal(SIGPIPE, SIG_IGN)
        #endif
    }

    public let codexPath: String

    public init(codexPath: String) {
        self.codexPath = codexPath
    }

    /// 抜粋テキストを stdin で渡して要約する（直近要約）。
    /// codex exec はプロンプト引数がある状態で stdin をパイプすると
    /// `<stdin>` ブロックとして追記する仕様を使う。
    public func summarizeTranscript(
        _ transcript: String,
        workingDirectory: String
    ) async throws -> String {
        try await run(
            buildArguments: { outputFile in
                [
                    "exec",
                    "--ephemeral",
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "--output-last-message", outputFile,
                    Self.marker + " 以下は AI コーディングエージェントとの会話の抜粋です。"
                        + "作業内容と現在の状況を簡潔に要約してください。",
                ]
            },
            workingDirectory: workingDirectory,
            stdinText: transcript
        )
    }

    /// セッションを ephemeral で resume して全体を要約する（全体要約）。
    public func summarizeFullSession(
        sessionId: String,
        workingDirectory: String
    ) async throws -> String {
        try await run(
            buildArguments: { outputFile in
                [
                    "exec",
                    "resume", sessionId,
                    "--ephemeral",
                    "--skip-git-repo-check",
                    "--output-last-message", outputFile,
                    Self.marker + " このセッションの作業内容と現在の状況を簡潔に要約してください。",
                ]
            },
            workingDirectory: workingDirectory
        )
    }

    private func run(
        buildArguments: (String) -> [String],
        workingDirectory: String,
        stdinText: String? = nil
    ) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_codex_" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let outputFile = tempDir.appendingPathComponent("last_message.txt")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // stdout/stderr は Pipe ではなくファイルに落とす（ClaudeSummarizer と同じ
        // 理由: パイプバッファ詰まり・EOF 未達・協調スレッド枯渇の 3 ハング要因回避）
        let stdoutFile = tempDir.appendingPathComponent("stdout.txt")
        let stderrFile = tempDir.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = buildArguments(outputFile.path)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = try FileHandle(forWritingTo: stdoutFile)
        process.standardError = try FileHandle(forWritingTo: stderrFile)

        Self.ignoreSIGPIPE()
        do {
            try process.run()
        } catch {
            throw SummarizeError("failed to start codex: \(error.localizedDescription)")
        }

        if let stdinText {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdinText.utf8))
            } catch {
                // ignore: broken pipe when the process exits early
            }
        }
        try? stdinPipe.fileHandleForWriting.close()

        // 終了を待つ（stdin を close 済みなので必ず終了する）
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        let stdoutData = (try? Data(contentsOf: stdoutFile)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrFile)) ?? Data()

        let exitCode = process.terminationStatus
        guard exitCode == 0 else {
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SummarizeError("codex exited with \(exitCode): \(detail)")
        }

        do {
            let result = try String(contentsOf: outputFile, encoding: String.Encoding.utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else {
                throw SummarizeError("codex returned an empty summary")
            }
            return result
        } catch let error as SummarizeError {
            throw error
        } catch {
            throw SummarizeError("codex did not produce a summary")
        }
    }
}
