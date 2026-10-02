import Foundation

/// pi セッション 1 件分の抽出結果。
public struct PiSessionEntry: Equatable {
    public let sessionId: String
    public let projectPath: String
    public let lastPrompt: String
    public let updatedAt: Date

    public init(sessionId: String, projectPath: String,
                lastPrompt: String, updatedAt: Date) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.lastPrompt = lastPrompt
        self.updatedAt = updatedAt
    }
}

/// pi（この coding agent）のセッション保存
/// （`~/.pi/agent/sessions/<cwd毎>/<ts>_<id>.jsonl`）を読む。
/// リファレンス実装: packages/core/lib/src/agent/pi/pi_session_history_reader.dart
///
/// JSONL の先頭行にセッションヘッダ（`type: session`）があり、`id` / `cwd` /
/// 開始時刻を持つ。それ以降はツリー構造のイベント行で、`message`
/// （user / assistant）が会話本体。壊れた行・読めないファイルはスキップする（E 系と同じ方針）。
public final class PiSessionHistoryReader {
    private let sessionsDir: URL

    public init(sessionsDir: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.sessionsDir = sessionsDir
            ?? URL(fileURLWithPath: home + "/.pi/agent/sessions", isDirectory: true)
    }

    /// 全セッションを新しい順で返す（全ファイルを走査するためここでは limit を切らない）。
    public func recentSessions(limit: Int = 20) throws -> [PiSessionEntry] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sessionsDir.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return [] }

        // 再帰的に .jsonl を集める（安定順）
        let entries = try FileManager.default
            .subpathsOfDirectory(atPath: sessionsDir.path)
            .filter { $0.hasSuffix(".jsonl") }
            .map { sessionsDir.appendingPathComponent($0) }
            .sorted { $0.path < $1.path }

        var out: [PiSessionEntry] = []
        for file in entries {
            if let entry = scanFile(file) {
                out.append(entry)
            }
        }
        out.sort { $0.updatedAt > $1.updatedAt }
        return Array(out.prefix(limit))
    }

    /// 1 ファイルからヘッダ・最終プロンプト・更新時刻を読む。読めなければ nil。
    private func scanFile(_ file: URL) -> PiSessionEntry? {
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            return nil
        }
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, let header = parseHeader(first) else { return nil }

        // 末尾の message から「最後のユーザー発言」と「最新時刻」を拾う
        var lastUserText = ""
        var newest = header.timestamp
        for line in lines.dropFirst() {
            if let ts = parseMessageTimestamp(line), ts > newest {
                newest = ts
            }
            if let userText = extractUserText(line), !userText.isEmpty {
                lastUserText = userText
            }
        }

        return PiSessionEntry(sessionId: header.id, projectPath: header.cwd,
                              lastPrompt: lastUserText, updatedAt: newest)
    }

    // MARK: - パース

    private struct Header {
        let id: String
        let cwd: String
        let timestamp: Date
    }

    private func parseHeader(_ line: String) -> Header? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decoded = try? MoostJSON.parse(trimmed),
              let map = decoded as? [String: Any],
              map["type"] as? String == "session",
              let id = map["id"] as? String
        else { return nil }
        let cwd = map["cwd"] as? String ?? ""
        let timestamp = (map["timestamp"] as? String).flatMap(parseISO) ?? epoch
        return Header(id: id, cwd: cwd, timestamp: timestamp)
    }

    /// message 行からロール user のテキスト（content の text 型）を返す。
    private func extractUserText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decoded = try? MoostJSON.parse(trimmed),
              let map = decoded as? [String: Any],
              map["type"] as? String == "message",
              let message = map["message"] as? [String: Any],
              message["role"] as? String == "user",
              let content = message["content"] as? [Any]
        else { return nil }
        var texts: [String] = []
        for part in content {
            if let partMap = part as? [String: Any],
               partMap["type"] as? String == "text",
               let text = partMap["text"] as? String {
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    texts.append(trimmedText)
                }
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: " ")
    }

    private func parseMessageTimestamp(_ line: String) -> Date? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decoded = try? MoostJSON.parse(trimmed),
              let map = decoded as? [String: Any],
              let timestamp = map["timestamp"] as? String
        else { return nil }
        return parseISO(timestamp)
    }

    private let epoch = ISOUTC.parse("1970-01-01T00:00:00.000Z") ?? Date(timeIntervalSince1970: 0)

    private func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        // ミリ秒なしの形式にも対応（Dart の DateTime.tryParse と同幅）
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
