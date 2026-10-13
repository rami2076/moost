import XCTest
@testable import MoostApp

/// 更新チェック（UpdateChecker）の純粋関数テスト。
/// ネットワークは使わず、API 応答の解釈とバージョン比較を検証する
/// （Flutter 版 Issue #12 の native 移植への回帰ゲート）。
final class UpdateCheckerTests: XCTestCase {
    // MARK: - decodeRelease（API 応答の解釈）

    func testDecodeReleaseNormalizesTagAndKeepsURL() throws {
        let json = """
        {
          "tag_name": "v2.0.2-macos",
          "html_url": "https://github.com/rami2076/moost/releases/tag/v2.0.2-macos"
        }
        """.data(using: .utf8)!
        let release = try XCTUnwrap(UpdateChecker.decodeRelease(json))
        XCTAssertEqual(release.version, "2.0.2-macos")
        XCTAssertEqual(release.url, "https://github.com/rami2076/moost/releases/tag/v2.0.2-macos")
    }

    func testDecodeReleaseIgnoresBrokenPayload() {
        XCTAssertNil(UpdateChecker.decodeRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.decodeRelease(Data("{\"foo\":1}".utf8)))
        XCTAssertNil(UpdateChecker.decodeRelease(Data("{\"tag_name\":\"\"}".utf8)))
    }

    // MARK: - evaluate（比較ロジック）

    func testEvaluateAvailableWhenLatestIsNewer() throws {
        let latest = UpdateChecker.Release(version: "2.0.2-macos", url: "u")
        let result = UpdateChecker.evaluate(current: "2.0.1-macos", latest: latest)
        XCTAssertEqual(result, .available(latest))
    }

    func testEvaluateUpToDateWhenEqual() throws {
        let latest = UpdateChecker.Release(version: "2.0.1-macos", url: "u")
        let result = UpdateChecker.evaluate(current: "2.0.1-macos", latest: latest)
        XCTAssertEqual(result, .upToDate(latest))
    }

    func testEvaluateUpToDateWhenCurrentIsNewer() throws {
        // 手元がリリースより先（開発ビルド等）でも「最新」表示で落ち着かせる
        let latest = UpdateChecker.Release(version: "2.0.1-macos", url: "u")
        let result = UpdateChecker.evaluate(current: "2.0.2-macos", latest: latest)
        XCTAssertEqual(result, .upToDate(latest))
    }

    func testEvaluateComparesOnlyMajorMinorPatch() throws {
        // プラットフォーム記号が違っても SemVer 本体で比較する
        let latest = UpdateChecker.Release(version: "2.1.0-linux", url: "u")
        let result = UpdateChecker.evaluate(current: "2.0.1-macos", latest: latest)
        XCTAssertEqual(result, .available(latest))
    }

    func testEvaluateFailedOnUnparseableVersion() {
        let latest = UpdateChecker.Release(version: "vNext-macos", url: "u")
        if case .failed = UpdateChecker.evaluate(current: "2.0.1-macos", latest: latest) {
            // OK
        } else {
            XCTFail("解釈不能なバージョンは failed になるべき")
        }
    }

    // MARK: - normalize / semverTriple

    func testNormalizeStripsV() {
        XCTAssertEqual(UpdateChecker.normalize("v2.0.2-macos"), "2.0.2-macos")
        XCTAssertEqual(UpdateChecker.normalize("2.0.1-macos"), "2.0.1-macos")
    }

    func testSemverTriple() {
        XCTAssertEqual(UpdateChecker.semverTriple("2.0.2-macos")?.0, 2)
        XCTAssertEqual(UpdateChecker.semverTriple("2.0.2-macos")?.1, 0)
        XCTAssertEqual(UpdateChecker.semverTriple("2.0.2-macos")?.2, 2)
        XCTAssertNil(UpdateChecker.semverTriple("2.0"))
        XCTAssertNil(UpdateChecker.semverTriple("abc"))
    }
}
