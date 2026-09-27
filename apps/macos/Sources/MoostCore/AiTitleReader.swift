import Foundation

/// セッション JSONL の末尾から最新の ai-title を取り出す（F2）。
/// リファレンス実装: packages/core/lib/src/agent/claude_code/ai_title_reader.dart
///
/// - セッション JSONL は数十 MB になりうるため全読みせず末尾チャンクだけ読む
/// - 逆順走査で最初にヒットしたものが最新（タイトルは会話中に更新される）
/// - 「ai-title」を含むが生 JSON でない行はスキップ（continue）
public final class AiTitleReader {
    private let projectsDirectory: URL
    private let tailBytes: Int

    public init(projectsDirectory: URL, tailBytes: Int = 64 * 1024) {
        self.projectsDirectory = projectsDirectory
        self.tailBytes = tailBytes
    }

    public func latestAiTitle(_ sessionId: String) throws -> String? {
        guard let sessionFile = findSessionFile(sessionId) else { return nil }

        let chunk: TailChunk
        do {
            chunk = try Self.readTail(of: sessionFile, tailBytes: tailBytes)
        } catch {
            let nsError = error as NSError
            let isMissing = (nsError.domain == NSCocoaErrorDomain && nsError.code == 260)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 2)
            if isMissing { return nil }
            throw error
        }

        guard var text = Self.decodeTail(chunk.data) else { return nil }
        // 末尾チャンク先頭が途中で切れた行なら不完全なので先頭行をすてる
        if chunk.truncated, let newline = text.firstIndex(of: "\n"), newline != text.startIndex {
            text = String(text[text.index(after: newline)...])
        }

        for line in text.components(separatedBy: "\n").reversed() {
            if !line.contains("\"ai-title\"") { continue }
            guard let decoded = try? MoostJSON.parse(line),
                  let json = decoded as? [String: Any],
                  json["type"] as? String == "ai-title",
                  let title = json["aiTitle"] as? String, !title.isEmpty else {
                continue
            }
            return title
        }
        return nil
    }

    /// ディレクトリのエンコード規則には依存せず、ファイル名（`<sessionId>.jsonl`）の
    /// 一意性だけを使う（design.md 3.2）
    private func findSessionFile(_ sessionId: String) -> URL? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: []) else {
            return nil
        }
        for entry in entries {
            let directory = projectsDirectory.appendingPathComponent(entry.lastPathComponent)
            let target = directory.appendingPathComponent(sessionId + ".jsonl")
            if fileManager.fileExists(atPath: target.path) {
                return target
            }
        }
        return nil
    }

    private struct TailChunk {
        let data: Data
        let truncated: Bool
    }

    private static func readTail(of url: URL, tailBytes: Int) throws -> TailChunk {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.closeFile() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let start = max(0, size - Int64(tailBytes))
        try handle.seek(toOffset: UInt64(start))
        let data = try handle.readDataToEndOfFile() ?? Data()
        return TailChunk(data: data, truncated: start > 0)
    }

    /// 先頭がマルチバイトの途中から切れた Data もデコードできるよう、
    /// 先頭最大 4 バイトまでずらして UTF-8 として成る文字列を探す
    private static func decodeTail(_ data: Data) -> String? {
        for drop in 0..<min(4, max(1, data.count)) {
            if let text = String(data: data.dropFirst(drop), encoding: .utf8) {
                return text
            }
        }
        return String(data: data, encoding: .utf8)
    }
}
