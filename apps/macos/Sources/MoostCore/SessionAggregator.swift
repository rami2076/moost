import Foundation

/// 複数エージェントの直近セッションを統合する（E5 / 多エージェント化）。
/// リファレンス実装: packages/core/lib/src/agent/adapter_registry.dart
/// の recentSessions（全 adapter をマージし新しい順に並べ limit で切る）。
///
/// 1 つの読み取り元の失敗（CLI 未導入・履歴破損等）で一覧全体を空にしないよう、
/// 失敗した読み取り元は空扱いにする。
public enum SessionAggregator {
    /// claude / codex / pi の 3 系統を統合する。fixture は同一（spec/ が唯一の正）。
    public static func recentSessions(
        claudeHistoryFile: URL,
        codexHistoryFile: URL,
        codexSessionsDir: URL,
        piSessionsDir: URL,
        limit: Int = 20
    ) -> [RecentSession] {
        let claude = (try? SessionHistoryReader(
            historyFile: claudeHistoryFile,
            agentId: ResumeCommand.claudeAgentId,
            excludeMarker: summaryMarker
        ).recentSessions(limit: limit)) ?? []

        let codex = codexRecentSessions(
            historyFile: codexHistoryFile, sessionsDir: codexSessionsDir, limit: limit)

        let pi = (try? PiSessionHistoryReader(sessionsDir: piSessionsDir)
            .recentSessions(limit: limit))
            .map { entries in
                entries.map {
                    RecentSession(agentId: ResumeCommand.piAgentId,
                                  sessionId: $0.sessionId,
                                  projectPath: $0.projectPath,
                                  lastPrompt: $0.lastPrompt,
                                  updatedAt: $0.updatedAt)
                }
            } ?? []

        return Array((claude + codex + pi)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit))
    }

    /// 実環境のホームディレクトリから統合一覧を読む（UI 用の便利関数）。
    public static func recentSessions(homeDirectory: String, limit: Int = 20) -> [RecentSession] {
        recentSessions(
            claudeHistoryFile: URL(fileURLWithPath: homeDirectory + "/.claude/history.jsonl"),
            codexHistoryFile: URL(fileURLWithPath: homeDirectory + "/.codex/history.jsonl"),
            codexSessionsDir: URL(fileURLWithPath: homeDirectory + "/.codex/sessions", isDirectory: true),
            piSessionsDir: URL(fileURLWithPath: homeDirectory + "/.pi/agent/sessions", isDirectory: true),
            limit: limit)
    }

    /// codex は rollout が消えたセッションを除外し、rollout から cwd を読む
    /// （リファレンス実装 codex_adapter.dart の recentSessions と同じ足取り）。
    private static func codexRecentSessions(
        historyFile: URL, sessionsDir: URL, limit: Int
    ) -> [RecentSession] {
        let entries = (try? CodexHistoryReader(
            historyFile: historyFile, excludeMarker: summaryMarker
        ).aggregatedEntries()) ?? []
        if entries.isEmpty { return [] }

        let rolloutIndex = (try? CodexRolloutReader(sessionsDir: sessionsDir).scan()) ?? [:]

        var selected: [(CodexHistoryEntry, URL)] = []
        for entry in entries {
            guard let rolloutFile = rolloutIndex[entry.sessionId] else { continue }
            selected.append((entry, rolloutFile))
            if selected.count >= limit { break }
        }

        return selected.map { pair in
            let cwd = (try? CodexRolloutReader(sessionsDir: sessionsDir)
                .readCwd(pair.1)) ?? nil
            return RecentSession(agentId: ResumeCommand.codexAgentId,
                                 sessionId: pair.0.sessionId,
                                 projectPath: cwd ?? "",
                                 lastPrompt: pair.0.lastPrompt,
                                 updatedAt: pair.0.updatedAt)
        }
    }

    /// 要約実行の除外マーカー（Dart の ClaudeSummarizer.marker / CodexSummarizer.marker と同値）。
    public static let summaryMarker = "[Moost\u{8981}\u{7d04}]"
}
