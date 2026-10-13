import Foundation
import XCTest
@testable import MoostApp

/// 更新チェック（リダイレクト方式: docs/app-update-check-methods.md 方式 7）のテスト。
/// ネットワークは使わず、URL パース・SemVer 比較・正規化の純粋関数を検証する。
/// （ネットワーク障害時の沈黙（nil を返す）は check() の全体契約として保証される。）
final class UpdateCheckerTests: XCTestCase {

    // MARK: - tagFromLocation

    func testTagFromLocationWithPlatformSuffix() {
        let url = URL(string: "https://github.com/rami2076/moost/releases/tag/v2.1.0-macos")!
        XCTAssertEqual(UpdateChecker.tagFromLocation(url), "v2.1.0-macos")
    }

    func testTagFromLocationPlainVersion() {
        let url = URL(string: "https://github.com/rami2076/moost/releases/tag/v2.0.1")!
        XCTAssertEqual(UpdateChecker.tagFromLocation(url), "v2.0.1")
    }

    func testTagFromLocationMissingTagSegment() {
        let url = URL(string: "https://github.com/rami2076/moost/releases/latest")!
        XCTAssertNil(UpdateChecker.tagFromLocation(url))
    }

    func testTagFromLocationTrailingSlash() {
        // Location に末尾スラッシュが付くケースは tagFromLocation で拾えないが、
        // 空セグメントを弾くことで誤ったタグを返さないことを保証する。
        let url = URL(string: "https://github.com/rami2076/moost/releases/tag/")!
        XCTAssertNil(UpdateChecker.tagFromLocation(url))
    }

    // MARK: - normalize

    func testNormalizeStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.normalize("v2.1.0-macos"), "2.1.0-macos")
        XCTAssertEqual(UpdateChecker.normalize("v2.0.1"), "2.0.1")
        XCTAssertEqual(UpdateChecker.normalize("2.1.0-macos"), "2.1.0-macos")
    }

    // MARK: - semverCore / compare

    func testSemverCoreIgnoresPlatformSuffix() {
        XCTAssertEqual(UpdateChecker.semverCore("2.1.0-macos"), [2, 1, 0])
        XCTAssertEqual(UpdateChecker.semverCore("v2.1.0-macos"), [2, 1, 0])
        XCTAssertEqual(UpdateChecker.semverCore("2.0.1-linux"), [2, 0, 1])
    }

    func testSemverCoreHandlesBuildMetadata() {
        XCTAssertEqual(UpdateChecker.semverCore("2.1.0+build42"), [2, 1, 0])
        XCTAssertEqual(UpdateChecker.semverCore("2.1.0-macos+build42"), [2, 1, 0])
    }

    func testSemverCoreRejectsGarbage() {
        XCTAssertNil(UpdateChecker.semverCore("latest"))
        XCTAssertNil(UpdateChecker.semverCore(""))
        XCTAssertNil(UpdateChecker.semverCore("v"))
    }

    func testSemverCorePadsMissingComponents() {
        // タグが `v2.1` のような省略表記でも i686 世代のように比較できる。
        XCTAssertEqual(UpdateChecker.semverCore("v2.1"), [2, 1])
    }

    // MARK: - isNewer

    func testIsNewerPlatformSuffixedTag() {
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v2.1.0-macos", current: "2.0.1-macos"))
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v2.0.3-macos", current: "2.0.2-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v2.0.1-macos", current: "2.0.2-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v2.0.2-macos", current: "2.0.2-macos"))
    }

    func testIsNewerIgnoresPlatformSuffixMismatch() {
        // 2.1.0-linux と 2.0.1-macos: プラットフォームの違いはあっても本体が新しければ true
        // （SemVer 本体だけを比較する仕様。プラットフォームごとにタグを分ける規約のため）。
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v2.1.0-linux", current: "2.0.1-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v2.0.1-linux", current: "2.0.2-macos"))
    }

    func testIsNewerMajorMinorPatch() {
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v3.0.0-macos", current: "2.99.99-macos"))
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v2.10.0-macos", current: "2.9.9-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v2.0.0-macos", current: "2.0.0-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v1.9.9-macos", current: "2.0.0-macos"))
    }

    func testIsNewerWithGarbageTagIsFalse() {
        XCTAssertFalse(UpdateChecker.isNewer(tag: "not-a-version", current: "2.0.1-macos"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v2.0.2-macos", current: "garbage"))
    }
}
