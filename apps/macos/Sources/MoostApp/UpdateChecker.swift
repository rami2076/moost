import Foundation

/// 更新チェック（Flutter 版 Issue #12 の native 移植）。
/// GitHub Releases API（`/releases/latest`、prerelease は返らない）を参照し、
/// 現在のアプリバージョン（AppInfo.displayVersion）と比較する。
/// 移行計画 5.2「アプリ内更新通知（v1.10 系）は GitHub Releases API の
/// 読み取りで継続する」に基づく。
struct UpdateChecker {
    struct Release: Equatable {
        /// 正規化済みタグ（例: "v2.0.2-macos" → "2.0.2-macos"）
        let version: String
        let url: String
    }

    enum Result: Equatable {
        /// 新しいバージョンあり
        case available(Release)
        /// 最新版（または手元の方が新しい）
        case upToDate(Release)
        /// 取得失敗（オフライン / API エラー / 応答解釈不能）
        case failed(String)
    }

    static let endpoint =
        URL(string: "https://api.github.com/repos/rami2076/moost/releases/latest")!

    /// ネットワークを伴うチェック（設定画面のボタン / 表示時から呼ぶ）。
    func check(currentVersion: String) async -> Result {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Moost/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("更新サーバーがエラーを返しました")
            }
            guard let release = Self.decodeRelease(data) else {
                return .failed("更新情報を解釈できませんでした")
            }
            return Self.evaluate(current: currentVersion, latest: release)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// API 応答 JSON から Release を組み立てる（テストはここを直接叩く）。
    static func decodeRelease(_ data: Data) -> Release? {
        struct Payload: Decodable {
            let tagName: String
            let htmlUrl: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }
        let version = normalize(payload.tagName)
        guard !version.isEmpty, !payload.htmlUrl.isEmpty else { return nil }
        return Release(version: version, url: payload.htmlUrl)
    }

    /// 現行バージョンと最新リリースを比較して結果を返す（純粋関数・テスト対象）。
    static func evaluate(current: String, latest: Release) -> Result {
        guard let currentTriple = semverTriple(current),
              let latestTriple = semverTriple(latest.version) else {
            return .failed("バージョン番号を比較できませんでした")
        }
        if compareTriples(latestTriple, currentTriple) > 0 {
            return .available(latest)
        }
        return .upToDate(latest)
    }

    /// "v2.0.2-macos" → "2.0.2-macos"。先頭の v を除くだけ。
    /// （プラットフォーム記号は比較には使わず、表示・URL にのみ残す）
    static func normalize(_ tagName: String) -> String {
        var s = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") { s.removeFirst() }
        return s
    }

    /// "2.0.2-macos" → (2,0,2)。解釈できなければ nil。
    static func semverTriple(_ version: String) -> (Int, Int, Int)? {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        let parts = core.split(separator: ".")
        guard parts.count >= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        return (major, minor, patch)
    }

    static func compareTriples(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        if a.0 != b.0 { return a.0 > b.0 ? 1 : -1 }
        if a.1 != b.1 { return a.1 > b.1 ? 1 : -1 }
        if a.2 != b.2 { return a.2 > b.2 ? 1 : -1 }
        return 0
    }
}
