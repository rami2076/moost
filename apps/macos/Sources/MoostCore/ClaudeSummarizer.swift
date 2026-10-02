import Foundation

/// `claude -p` によるセッション要約の実行。
/// リファレンス実装: packages/core/lib/src/agent/claude_code/claude_summarizer.dart
///
/// - モデルは haiku 固定（requirements.md 3.6）
/// - 全体要約のフォークセッションが一覧に混ざらないよう、プロンプト先頭に
///   マーカーを入れる（design.md 5 章）
/// - Moost 自身のプロセスが Claude Code 由来の環境変数を保持していると、
///   そのまま子プロセスに継承され子セッションと誤認識されうるため除去する
///   （Issue #52）
/// - サブプロセス実行の実装メモ（Swift 6 の協調スケジューラとブロッキング
///   FileHandle の相互作用でハングしたため、ファイルリダイレクト方式を採用）:
///   - stdout/stderr は **ファイル** にリダイレクトする。Pipe + 
///     readDataToEndOfFile は (a) パイプバッファ詰まり、(b) 親側の書き込み端を
///     閉じ忘れると EOF が来ない、(c) Task.detached 内のブロッキング read が
///     Swift 協調スレッドプールを枯渇させる、という 3 つのハング要因がある。
///   - 子プロセスの終了は terminationHandler + DispatchSemaphore で待つ。
///   - stdin 書き込み中の broken pipe は許容（SIGPIPE 無視 + catch）。
public final class ClaudeSummarizer: Sendable {
    /// 要約用フォークセッションの除外マーカー。
    public static let marker = "[Moost\u{8981}\u{7d04}]"

    /// 子プロセスが stdin を読まずに終了した場合、FileHandle.write は
    /// SIGPIPE でこのプロセスごと落ちる（dart:io は SIGPIPE を無視するが
    /// Swift はしない）。ここで明示的に無視し、書き込み側は EPIPE を
    /// catch で握りつぶして exitCode ベースのエラーに倒す。
    private static func ignoreSIGPIPE() {
        #if canImport(Darwin)
        signal(SIGPIPE, SIG_IGN)
        #elseif canImport(Glibc)
        signal(SIGPIPE, SIG_IGN)
        #endif
    }

    static let model = "haiku"

    public let claudePath: String

    /// 除去処理のベースとなる環境（テスト用の注入ポイント。
    /// nil なら実際のプロセス環境を使う）。
    private let baseEnvironment: [String: String]

    public init(claudePath: String, environment: [String: String]? = nil) {
        self.claudePath = claudePath
        self.baseEnvironment = environment ?? ProcessInfo.processInfo.environment
    }

    /// 抜粋テキストを stdin で渡して要約する（直近要約）。
    public func summarizeTranscript(
        _ transcript: String,
        workingDirectory: String
    ) async throws -> String {
        try await run(
            arguments: [
                "-p",
                "--model", Self.model,
                Self.marker + " 以下は AI コーディングエージェントとの会話の抜粋です。"
                    + "作業内容と現在の状況を簡潔に要約してください。",
            ],
            workingDirectory: workingDirectory,
            stdinText: transcript
        )
    }

    /// セッションを fork して全体を要約する（全体要約）。
    public func summarizeFullSession(
        sessionId: String,
        workingDirectory: String
    ) async throws -> String {
        try await run(
            arguments: [
                "-p",
                "--resume", sessionId,
                "--fork-session",
                "--model", Self.model,
                Self.marker + " このセッションの作業内容と現在の状況を簡潔に要約してください。",
            ],
            workingDirectory: workingDirectory
        )
    }

    private func run(
        arguments: [String],
        workingDirectory: String,
        stdinText: String? = nil
    ) async throws -> String {
        let workDir = URL(fileURLWithPath: workingDirectory)

        // 一時ディレクトリに stdout/stderr を落とす
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_claude_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stdoutFile = tempDir.appendingPathComponent("stdout.txt")
        let stderrFile = tempDir.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = arguments
        process.currentDirectoryURL = workDir
        // includeParentEnvironment の既定では environment は親に「追加」される
        // だけでキーを消せないため、フィルタ済みの環境そのものを渡す
        process.environment = ClaudeEnvironment.withoutInternalEnv(baseEnvironment)

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = try FileHandle(forWritingTo: stdoutFile)
        process.standardError = try FileHandle(forWritingTo: stderrFile)

        Self.ignoreSIGPIPE()
        do {
            try process.run()
        } catch {
            throw SummarizeError("failed to start claude: \(error.localizedDescription)")
        }

        // 子プロセスの stdin に書き込む。プロセスが stdin を読まずに終了した
        // 場合の broken pipe は許容する（エラーは exitCode / stderr 側で検知する）
        if let stdinText {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(stdinText.utf8))
            } catch {
                // ignore: broken pipe when the process exits early
            }
        }
        try? stdinPipe.fileHandleForWriting.close()

        // 終了を待つ（stdin を close 済みなので必ず終了する）。
        // DispatchSemaphore.wait() は Swift 6 の async コンテキストでは
        // 使えないため、terminationHandler + continuation で協調的に待つ。
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
            throw SummarizeError("claude exited with \(exitCode): \(detail)")
        }
        return (String(data: stdoutData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
