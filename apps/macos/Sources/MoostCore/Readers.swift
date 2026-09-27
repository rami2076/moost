import Foundation

/// 直近セッション一覧の元データ読み取り（E1-E5, E6-E7）。
/// リファレンス実装: packages/core/lib/src/agent/claude_code/session_history_reader.dart
///
/// 壊れた行・空行はスキップ（内部フォーマット変更で落ちない）。
/// フォーク除外は「行単位」の検索であることに留意すること（E3。
/// マーカー行を 1 つでも含むセッションを全除外すると正常セッションが消える）。

private func readLines(_ file: URL) throws -> [String] {
    let text: String
    do {
        text = try String(contentsOf: file, encoding: String.Encoding.utf8)
    } catch {
        let nsError = error as NSError
        let isMissing = (nsError.domain == NSCocoaErrorDomain && nsError.code == 260)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 2)
        if isMissing { return [] }
        throw error
    }
    return text.components(separatedBy: "\n").map { String($0) }
}

private func decodeLine(_ line: String) -> [String: Any]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return (try? MoostJSON.parse(trimmed)) as? [String: Any]
}

public struct CodexHistoryEntry: Equatable {
    public let sessionId: String
    public let lastPrompt: String
    public let updatedAt: Date
}

/// claude 系 history.jsonl（display / timestamp[ms] / project / sessionId）
public final class SessionHistoryReader {
    private struct Entry {
        let sessionId: String
        let display: String
        let project: String
        let timestampMilliseconds: Int
    }

    private let historyFile: URL
    private let agentId: String
    private let excludeMarker: String

    public init(historyFile: URL, agentId: String, excludeMarker: String) {
        self.historyFile = historyFile
        self.agentId = agentId
        self.excludeMarker = excludeMarker
    }

    public func recentSessions(limit: Int = 20) throws -> [RecentSession] {
        var latestBySession: [String: Entry] = [:]
        for line in try readLines(historyFile) {
            guard let json = decodeLine(line),
                  let display = json["display"] as? String,
                  let timestamp = JsonScalar.integer(line, "timestamp"),
                  let project = json["project"] as? String,
                  let sessionId = json["sessionId"] as? String else {
                continue
            }
            if display.hasPrefix(excludeMarker) { continue }
            if let existing = latestBySession[sessionId],
               existing.timestampMilliseconds >= timestamp {
                continue
            }
            latestBySession[sessionId] = Entry(sessionId: sessionId, display: display,
                                                project: project, timestampMilliseconds: timestamp)
        }
        return latestBySession.values
            .sorted { $0.timestampMilliseconds > $1.timestampMilliseconds }
            .prefix(limit)
            .map {
                RecentSession(agentId: agentId, sessionId: $0.sessionId,
                              projectPath: $0.project, lastPrompt: $0.display,
                              updatedAt: Date(ms: Double($0.timestampMilliseconds)))
            }
    }
}

/// codex 系 history.jsonl（session_id / ts[epoch 秒] / text。project を持たない）
public final class CodexHistoryReader {
    private struct Line {
        let sessionId: String
        let text: String
        let timestamp: Int
    }

    private let historyFile: URL
    private let excludeMarker: String

    public init(historyFile: URL, excludeMarker: String) {
        self.historyFile = historyFile
        self.excludeMarker = excludeMarker
    }

    /// 全セッションを最新順で返す（rollout 有無で間引くためここでは limit を切らない）
    public func aggregatedEntries() throws -> [CodexHistoryEntry] {
        var latestBySession: [String: Line] = [:]
        for line in try readLines(historyFile) {
            guard let json = decodeLine(line),
                  let sessionId = json["session_id"] as? String,
                  let timestamp = JsonScalar.integer(line, "ts"),
                  let text = json["text"] as? String else {
                continue
            }
            if text.hasPrefix(excludeMarker) { continue }
            if let existing = latestBySession[sessionId], existing.timestamp >= timestamp {
                continue
            }
            latestBySession[sessionId] = Line(sessionId: sessionId, text: text, timestamp: timestamp)
        }
        return latestBySession.values
            .sorted { $0.timestamp > $1.timestamp }
            .map {
                CodexHistoryEntry(sessionId: $0.sessionId, lastPrompt: $0.text,
                                  updatedAt: Date(seconds: Double($0.timestamp)))
            }
    }
}
