import Foundation

/// セッション要約の実行（エージェント別ディスパッチ）。
/// リファレンス実装: 各 agent adapter の summarize（claude_code_adapter.dart /
/// codex_adapter.dart / pi_adapter.dart の対応部分）。
///
/// - claude / codex: 直近は「抜粋 → ヘッドレス CLI 実行」、全体は
///   `--fork-session` / `resume --ephemeral` で行う
/// - pi: ヘッドレス要約コマンドを持たないため、抽出テキストをそのまま返す
///   （API 消費ゼロ）
/// - cwd が取れなかったセッションでも要約は動かせるように、codex は
///   projectPath が空なら home で実行する
public final class SessionSummarizer: Sendable {
    public let home: String
    public let claudePathOverride: String

    public init(home: String, claudePathOverride: String = "") {
        self.home = home
        self.claudePathOverride = claudePathOverride
    }

    public func summarize(
        session: RecentSession,
        scope: SummaryScope,
        rallies: Int = 1
    ) async throws -> String {
        switch session.agentId {
        case ResumeCommand.claudeAgentId:
            return try await summarizeClaude(session: session, scope: scope, rallies: rallies)
        case ResumeCommand.codexAgentId:
            return try await summarizeCodex(session: session, scope: scope, rallies: rallies)
        case ResumeCommand.piAgentId:
            return try summarizePi(session: session, scope: scope, rallies: rallies)
        default:
            throw SummarizeError("unknown agent: \(session.agentId)")
        }
    }

    private func summarizeClaude(
        session: RecentSession,
        scope: SummaryScope,
        rallies: Int
    ) async throws -> String {
        guard let claudePath = AgentPathDetect.claude(override: claudePathOverride) else {
            throw SummarizeError("claude command not found: set the path in settings")
        }
        let summarizer = ClaudeSummarizer(claudePath: claudePath)
        let projectsDir = URL(
            fileURLWithPath: home + "/.claude/projects", isDirectory: true)
        switch scope {
        case .recent:
            let extractor = ClaudeTranscriptExtractor(projectsDir: projectsDir)
            guard let transcript = try extractor.extract(
                sessionId: session.sessionId, rallies: rallies) else {
                throw SummarizeError("no transcript found for the session")
            }
            return try await summarizer.summarizeTranscript(
                transcript, workingDirectory: session.projectPath)
        case .full:
            return try await summarizer.summarizeFullSession(
                sessionId: session.sessionId,
                workingDirectory: session.projectPath)
        }
    }

    private func summarizeCodex(
        session: RecentSession,
        scope: SummaryScope,
        rallies: Int
    ) async throws -> String {
        guard let codexPath = AgentPathDetect.codex() else {
            throw SummarizeError("codex command not found: install codex or add it to PATH")
        }
        let summarizer = CodexSummarizer(codexPath: codexPath)
        let workingDirectory = session.projectPath.isEmpty ? home : session.projectPath
        switch scope {
        case .recent:
            let extractor = CodexTranscriptExtractor(
                rolloutReader: CodexRolloutReader(
                    sessionsDir: URL(
                        fileURLWithPath: home + "/.codex/sessions", isDirectory: true)))
            guard let transcript = try extractor.extract(
                sessionId: session.sessionId, rallies: rallies) else {
                throw SummarizeError("no transcript found for the session")
            }
            return try await summarizer.summarizeTranscript(
                transcript, workingDirectory: workingDirectory)
        case .full:
            return try await summarizer.summarizeFullSession(
                sessionId: session.sessionId,
                workingDirectory: workingDirectory)
        }
    }

    private func summarizePi(
        session: RecentSession,
        scope: SummaryScope,
        rallies: Int
    ) throws -> String {
        let extractor = PiTranscriptExtractor(
            sessionsDir: URL(
                fileURLWithPath: home + "/.pi/agent/sessions", isDirectory: true))
        let text = extractor.extract(
            sessionId: session.sessionId,
            full: scope == .full,
            rallies: rallies)
        if text.isEmpty {
            throw SummarizeError("no transcript found for the session")
        }
        return text
    }
}
