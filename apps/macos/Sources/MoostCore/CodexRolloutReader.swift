import Foundation

/// `~/.codex/sessions/` 配下の rollout JSONL を扱う。
/// リファレンス実装: packages/core/lib/src/agent/codex/codex_rollout_reader.dart
///
/// セッション本体は `sessions/YYYY/MM/DD/rollout-<日時>-<sessionId>.jsonl`。
/// 日付ディレクトリの構造には依存せず、「ファイル名末尾が `-<sessionId>.jsonl`」
/// という性質だけを使って再帰走査で見つける（AiTitleReader と同じ方針）。
public final class CodexRolloutReader: Sendable {
    private let sessionsDir: URL

    public init(sessionsDir: URL) {
        self.sessionsDir = sessionsDir
    }

    private static let rolloutName = try! NSRegularExpression(
        pattern: "rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
            + "[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\\.jsonl$")

    /// sessionId → rollout ファイルの索引を作る。
    /// 同一 sessionId の rollout が複数ある場合（resume 等）は、
    /// ファイル名に日時が入っている性質を使い辞書順で最新を採用する。
    public func scan() throws -> [String: URL] {
        var index: [String: URL] = [:]
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sessionsDir.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return index }

        for path in try FileManager.default.subpathsOfDirectory(atPath: sessionsDir.path) {
            guard path.hasSuffix(".jsonl") else { continue }
            let file = sessionsDir.appendingPathComponent(path)
            let name = file.lastPathComponent
            guard let match = Self.rolloutName.firstMatch(
                in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
                match.numberOfRanges > 1,
                let idRange = Range(match.range(at: 1), in: name)
            else { continue }
            let sessionId = String(name[idRange])
            if let existing = index[sessionId] {
                if existing.lastPathComponent.compare(name) == .orderedAscending {
                    index[sessionId] = file
                }
            } else {
                index[sessionId] = file
            }
        }
        return index
    }

    /// rollout 先頭の `session_meta` 行からセッションの作業ディレクトリを返す。
    /// session_meta は通常 1 行目だが、多少ずれても拾えるよう先頭数行を見る。
    /// 見つからない・読めない場合は nil。
    public func readCwd(_ rolloutFile: URL) throws -> String? {
        let text: String
        do {
            text = try String(contentsOf: rolloutFile, encoding: .utf8)
        } catch {
            let nsError = error as NSError
            let isMissing = (nsError.domain == NSCocoaErrorDomain && nsError.code == 260)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 2)
            if isMissing { return nil }
            throw error
        }

        var count = 0
        for line in text.components(separatedBy: "\n") {
            count += 1
            if count > 10 { break }
            if !line.contains("\"session_meta\"") { continue }
            guard let decoded = try? MoostJSON.parse(line),
                  let map = decoded as? [String: Any],
                  map["type"] as? String == "session_meta",
                  let payload = map["payload"] as? [String: Any]
            else { continue }
            return payload["cwd"] as? String
        }
        return nil
    }
}
