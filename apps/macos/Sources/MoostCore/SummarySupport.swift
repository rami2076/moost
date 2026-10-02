import Foundation

/// セッション要約の対象範囲。
/// リファレンス実装: packages/core/lib/src/agent/agent_adapter.dart の SummaryScope。
public enum SummaryScope: Equatable, Sendable {
    /// 直近 N ラリーの抜粋を渡す（高速・低コスト）。
    case recent
    /// セッション全体を対象にする（時間と利用枠を多く消費）。
    case full
}

/// 要約実行に失敗したときに投げる。ユーザーに見せられるメッセージを持つ。
/// リファレンス実装: summarize_exception.dart。
public struct SummarizeError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// セッション要約のメモリキャッシュ（design.md 5 章 / ADR-002）。
/// 要約は永続化せず、アプリ常駐中のみ生きる。目的は同じセッション詳細を
/// 開き直したときに `claude -p` を再実行しないこと（時間と利用料の節約）。
/// キーは セッションID × 要約範囲（scope + ラリー数）。
/// リファレンス実装: packages/core/lib/src/summary_cache.dart。
public final class SummaryCache: @unchecked Sendable {
    private var entries: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    private func key(_ sessionId: String, _ scope: SummaryScope, _ rallies: Int) -> String {
        switch scope {
        case .full: return sessionId + ":full"
        case .recent: return sessionId + ":recent" + String(rallies)
        }
    }

    public func get(_ sessionId: String, scope: SummaryScope, rallies: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key(sessionId, scope, rallies)]
    }

    public func put(_ sessionId: String, scope: SummaryScope, rallies: Int, summary: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key(sessionId, scope, rallies)] = summary
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
