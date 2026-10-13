import Foundation

/// 更新チェック（Flutter 版 Issue #12 の native 移植。
/// docs/app-update-check-methods.md の方式 7 = リダイレクト方式）。
///
/// Web の `releases/latest` に HEAD を打ち、302 の `Location`
/// （…/releases/tag/vX.Y.Z）からタグを読む。API ではないのでレート制限がなく、
/// JSON / XML のパースも不要。最新安定版のみを指す（prerelease / draft は除外）。
///
/// 失敗（オフライン・想定外レスポンス・タイムアウト）は沈黙して nil を返す。
/// 通知機能の不具合でアプリ本体を壊さない。
struct UpdateInfo: Equatable {
    /// 例: "2.1.0-macos"（先頭の v は含まない。プラットフォーム記号付き）
    let version: String
    let releaseURL: URL
}

enum UpdateChecker {
    static let endpoint = URL(string: "https://github.com/rami2076/moost/releases/latest")!

    /// 新しいバージョンがあれば [UpdateInfo]、なければ nil。
    static func check(currentVersion: String) async -> UpdateInfo? {
        let delegate = NoRedirectDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.setValue("Moost/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (300..<400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let releaseURL = URL(string: location, relativeTo: endpoint)?.absoluteURL,
                  let tag = tagFromLocation(releaseURL) else {
                return nil
            }
            guard isNewer(tag: tag, current: currentVersion) else { return nil }
            return UpdateInfo(version: normalize(tag), releaseURL: releaseURL)
        } catch {
            return nil
        }
    }

    /// `…/releases/tag/v2.1.0-macos` の末尾からタグを取り出す。
    /// パスに tag セグメントが無ければ nil。
    static func tagFromLocation(_ url: URL) -> String? {
        let segments = url.pathComponents
        guard let tagIndex = segments.lastIndex(of: "tag"),
              tagIndex + 1 < segments.count else {
            return nil
        }
        let tag = segments[tagIndex + 1]
        guard !tag.isEmpty else { return nil }
        return tag
    }

    /// "v2.1.0-macos" → "2.1.0-macos"（先頭の v を除くだけ）。
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") { s.removeFirst() }
        return s
    }

    /// タグ（またはバージョン文字列）が現行より新しいか。
    /// プラットフォーム記号（-macos 等）は SemVer 本体の比較に使わない。
    static func isNewer(tag: String, current: String) -> Bool {
        guard let tagCore = semverCore(tag),
              let currentCore = semverCore(current) else {
            return false
        }
        return compare(tagCore, currentCore) > 0
    }

    /// "2.1.0-macos"/"v2.1.0"/"2.1.0+build" から数値列を取り出す。
    static func semverCore(_ version: String) -> [Int]? {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") { v.removeFirst() }
        let core = v.split(separator: "-").first.map(String.init) ?? v
        let parts = core.split(separator: "+").first.map(String.init) ?? core
        let nums = parts.split(separator: ".").compactMap { Int($0) }
        guard !nums.isEmpty else { return nil }
        return nums
    }

    /// 数値列同士の比較（不足成分は 0 扱い）。
    static func compare(_ a: [Int], _ b: [Int]) -> Int {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}

/// リダイレクトを追わずに 302 のレスポンス（Location ヘッダ）を受け取るための
/// URLSession デリゲート。URLSession はデフォルトでリダイレクトを追跡してしまう。
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
