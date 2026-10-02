import Foundation

/// 要約用の会話抜粋（transcript）をエージェント別セッションファイルから作る。
/// リファレンス実装:
/// - packages/core/lib/src/agent/claude_code/transcript_extractor.dart
/// - packages/core/lib/src/agent/codex/codex_transcript_extractor.dart
/// - packages/core/lib/src/agent/pi/pi_transcript_extractor.dart
///
/// ラリー = ユーザープロンプト 1 つと、それに続くアシスタント応答のまとまり。
/// パースできない行・関係ない行はスキップする。呼び出し側の明示操作でしか
/// 走らないため全行読みでよい（Dart リファレンスと同じ足取り）。

// MARK: - 共通ヘルパー

private func readJSONLines(_ url: URL) -> [String] {
    let text: String
    do {
        text = try String(contentsOf: url, encoding: String.Encoding.utf8)
    } catch {
        return []
    }
    return text.components(separatedBy: "\n").map { String($0) }
}

private func decodeObject(_ line: String) -> [String: Any]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return (try? MoostJSON.parse(trimmed)) as? [String: Any]
}

private struct Rally {
    let userText: String
    var assistantTexts: [String] = []
}

private func renderTranscript(_ rallies: [Rally]) -> String {
    var buffer = ""
    for rally in rallies {
        buffer += "User: \(rally.userText)\n"
        for text in rally.assistantTexts {
            buffer += "Assistant: \(text)\n"
        }
        buffer += "\n"
    }
    return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Claude

/// claude セッション JSONL から直近 N ラリーの会話抜粋を取り出す。
/// `~/.claude/projects/<cwd-dir>/<sessionId>.jsonl` を想定。
public final class ClaudeTranscriptExtractor: Sendable {
    public let projectsDir: URL

    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
    }

    public func extract(sessionId: String, rallies: Int = 1) throws -> String? {
        guard let file = findSessionFile(sessionId) else { return nil }

        var collected: [Rally] = []
        for line in readJSONLines(file) {
            guard let message = parseMessage(line) else { continue }
            if message.role == "user" {
                collected.append(Rally(userText: message.text))
                // メモリを抑えるため保持は直近分だけにする
                if collected.count > rallies {
                    collected.removeFirst()
                }
            } else if !collected.isEmpty {
                collected[collected.count - 1].assistantTexts.append(message.text)
            }
        }

        if collected.isEmpty { return nil }
        return renderTranscript(collected)
    }

    private func findSessionFile(_ sessionId: String) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil),
            contents.contains(where: { $0.hasDirectoryPath })
        else { return nil }
        for url in contents {
            guard url.hasDirectoryPath else { continue }
            let candidate = url.appendingPathComponent(sessionId + ".jsonl")
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private struct Message {
        let role: String
        let text: String
    }

    private func parseMessage(_ line: String) -> Message? {
        // 安いフィルタ: user / assistant メッセージ行だけを対象にする
        guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") else {
            return nil
        }
        guard let decoded = decodeObject(line),
              decoded["isSidechain"] as? Bool != true,
              let type = decoded["type"] as? String,
              type == "user" || type == "assistant",
              let message = decoded["message"] as? [String: Any],
              let text = extractContentText(message["content"])
        else { return nil }
        return Message(role: type, text: text)
    }

    /// content は文字列またはブロック配列（`{"type":"text","text":...}` 等）。
    private func extractContentText(_ content: Any?) -> String? {
        if let text = content as? String {
            return text
        }
        if let blocks = content as? [Any] {
            var parts: [String] = []
            for block in blocks {
                if let dict = block as? [String: Any],
                   dict["type"] as? String == "text",
                   let text = dict["text"] as? String {
                    parts.append(text)
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return nil
    }
}

// MARK: - Codex

/// codex rollout JSONL から直近 N ラリーの会話抜粋を取り出す。
/// 対象は `response_item` の user / assistant メッセージ。
/// システム由来のコンテキストも user ロールで記録されるため、既知の
/// プレフィックスで始まるものは除外する。
public final class CodexTranscriptExtractor: Sendable {
    /// codex が user ロールで記録するシステム由来テキストの既知プレフィックス。
    static let systemUserPrefixes = [
        "<environment_context>",
        "<user_instructions>",
        "<user_action>",
        "<turn_aborted>",
        "<permissions",
    ]

    public let rolloutReader: CodexRolloutReader

    public init(rolloutReader: CodexRolloutReader) {
        self.rolloutReader = rolloutReader
    }

    public func extract(sessionId: String, rallies: Int = 1) throws -> String? {
        let index = try rolloutReader.scan()
        guard let file = index[sessionId] else { return nil }

        var collected: [Rally] = []
        for line in readJSONLines(file) {
            guard let message = parseMessage(line) else { continue }
            if message.role == "user" {
                collected.append(Rally(userText: message.text))
                if collected.count > rallies {
                    collected.removeFirst()
                }
            } else if !collected.isEmpty {
                collected[collected.count - 1].assistantTexts.append(message.text)
            }
        }

        if collected.isEmpty { return nil }
        return renderTranscript(collected)
    }

    private struct Message {
        let role: String
        let text: String
    }

    private func parseMessage(_ line: String) -> Message? {
        // 安いフィルタ: メッセージを含みうる response_item 行だけを対象にする
        guard line.contains("\"type\":\"response_item\"") ||
                line.contains("\"type\":\"message\"") else {
            return nil
        }
        guard let decoded = decodeObject(line),
              decoded["type"] as? String == "response_item",
              let payload = decoded["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              let role = payload["role"] as? String,
              role == "user" || role == "assistant",
              let text = extractContentText(payload["content"])
        else { return nil }
        if role == "user",
           Self.systemUserPrefixes.contains(where: { text.hasPrefix($0) }) {
            return nil
        }
        return Message(role: role, text: text)
    }

    /// content はブロック配列（`{"type":"input_text"|"output_text","text":...}`）。
    private func extractContentText(_ content: Any?) -> String? {
        guard let blocks = content as? [Any] else { return nil }
        var parts: [String] = []
        for block in blocks {
            guard let dict = block as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "input_text" || type == "output_text",
                  let text = dict["text"] as? String else { continue }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - pi

/// pi セッション JSONL から、要約用のプレーンテキストを組み立てる。
/// pi は対話セッションをツリー構造の JSONL で保存しており、`message` 行の
/// `message.role`（user/assistant）と `content[]` の text 型をたどる。
/// ヘッドレス要約コマンドを持たないため、この抽出結果をそのまま要約として
/// 返す（API 消費ゼロ）。
public final class PiTranscriptExtractor: Sendable {
    public let sessionsDir: URL

    public init(sessionsDir: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.sessionsDir = sessionsDir ??
            URL(fileURLWithPath: home + "/.pi/agent/sessions", isDirectory: true)
    }

    /// セッション [sessionId] のやり取りをテキスト化して返す。
    /// 対象ファイルが見つからない場合は空文字列。
    /// - full が false: 末尾 rallies * 2 メッセージ（直近のやり取り）
    /// - full が true: セッション全体
    public func extract(sessionId: String, full: Bool = false, rallies: Int = 1) -> String {
        guard let file = findSessionFile(sessionId) else { return "" }
        let messages = readMessages(file)
        guard !messages.isEmpty else { return "" }

        let selected: [PiMessage]
        if full {
            selected = messages
        } else if messages.count > rallies * 2 {
            selected = Array(messages.suffix(rallies * 2))
        } else {
            selected = messages
        }

        var buffer = ""
        for entry in selected {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            buffer += (entry.role == "user" ? "User: " : "Assistant: ") + text + "\n\n"
        }
        return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// sessionId（ヘッダの id）が一致するセッションファイルを探す。
    private func findSessionFile(_ sessionId: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]),
            fm.fileExists(atPath: sessionsDir.path)
        else { return nil }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if url.lastPathComponent.contains("_\(sessionId).jsonl") {
                return url
            }
            files.append(url)
        }

        // フォールバック: ヘッダの id と照合
        for file in files {
            let lines = readJSONLines(file)
            guard let first = lines.first,
                  first.contains("\"type\":\"session\""),
                  let decoded = decodeObject(first),
                  decoded["id"] as? String == sessionId
            else { continue }
            return file
        }
        return nil
    }

    private func readMessages(_ file: URL) -> [PiMessage] {
        var out: [PiMessage] = []
        for line in readJSONLines(file) {
            if let message = parseMessage(line) {
                out.append(message)
            }
        }
        return out
    }

    private struct PiMessage {
        let role: String
        let text: String
    }

    private func parseMessage(_ line: String) -> PiMessage? {
        guard let decoded = decodeObject(line),
              decoded["type"] as? String == "message",
              let message = decoded["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" || role == "assistant",
              let content = message["content"] as? [Any]
        else { return nil }

        var texts: [String] = []
        for part in content {
            if let dict = part as? [String: Any],
               dict["type"] as? String == "text",
               let text = dict["text"] as? String {
                texts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard !texts.isEmpty else { return nil }
        return PiMessage(role: role, text: texts.joined(separator: "\n"))
    }
}
