import Foundation
import XCTest
@testable import MoostApp

/// フッター更新ボタンの状態機械（Flutter 版 `_UpdateButtonState` の移植）のテスト。
/// ネットワーク・brew 実体は使わず、Mock で遷移だけを検証する。
@MainActor
final class UpdateButtonModelTests: XCTestCase {

    // MARK: - ヘルパー

    private let releaseInfo = UpdateInfo(
        version: "2.1.0-macos",
        releaseURL: URL(string: "https://github.com/rami2076/moost/releases/tag/v2.1.0-macos")!
    )

    private final class Captures: @unchecked Sendable {
        let lock = NSLock()
        var openedURLs: [URL] = []
        var copied: [String] = []
        var restarted = 0

        func recordOpen(_ url: URL) { lock.lock(); openedURLs.append(url); lock.unlock() }
        func recordCopy(_ text: String) { lock.lock(); copied.append(text); lock.unlock() }
        func recordRestart() { lock.lock(); restarted += 1; lock.unlock() }
        func read<T>(_ keyPath: KeyPath<Captures, T>) -> T {
            lock.lock(); defer { lock.unlock() }
            return self[keyPath: keyPath]
        }
    }

    private actor MockBrewUpdater: BrewUpdating {
        enum Behavior { case succeed, fail(String) }
        private let behavior: Behavior
        private(set) var runCount = 0
        private(set) var repairCount = 0

        init(behavior: Behavior) { self.behavior = behavior }

        func run() async throws {
            runCount += 1
            switch behavior {
            case .succeed: return
            case .fail(let message): throw BrewUpdateError.commandFailed(
                command: "brew upgrade --cask moost", exitCode: 1, detail: message)
            }
        }

        func repair() async throws {
            repairCount += 1
            switch behavior {
            case .succeed: return
            case .fail(let message): throw BrewUpdateError.commandFailed(
                command: "brew reinstall --cask moost", exitCode: 1, detail: message)
            }
        }
    }

    private func makeModel(
        update: UpdateInfo? = nil,
        broken: Bool = false,
        brewManaged: Bool = false,
        behavior: MockBrewUpdater.Behavior = .succeed
    ) -> (UpdateButtonModel, Captures, MockBrewUpdater) {
        let captures = Captures()
        let updater = MockBrewUpdater(behavior: behavior)
        let model = UpdateButtonModel(
            update: update,
            isInstallBroken: broken,
            isBrewManaged: { brewManaged },
            openURL: { captures.recordOpen($0) },
            copyText: { captures.recordCopy($0) },
            updater: updater,
            restart: { captures.recordRestart() }
        )
        return (model, captures, updater)
    }

    // MARK: - idle のタップ（分岐）

    func testManualInstallTapOpensReleasePageAndStaysIdle() {
        let (model, captures, _) = makeModel(update: releaseInfo, brewManaged: false)
        model.handleTap()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(captures.read(\.openedURLs), [releaseInfo.releaseURL])
    }

    func testBrewManagedTapGoesToConfirming() async {
        let (model, _, updater) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        XCTAssertEqual(model.phase, .confirming)
        let runCount = await updater.runCount
        XCTAssertEqual(runCount, 0)
    }

    func testBrokenTapGoesToConfirming() {
        let (model, _, _) = makeModel(update: nil, broken: true, brewManaged: false)
        model.handleTap()
        XCTAssertEqual(model.phase, .confirming)
    }

    func testNoUpdateNoTapEffect() {
        let (model, captures, _) = makeModel(update: nil, brewManaged: true)
        model.handleTap()
        XCTAssertEqual(model.phase, .confirming) // brew 管理なら確認に進む（update は無くても可）
        XCTAssertTrue(captures.read(\.openedURLs).isEmpty)
    }

    // MARK: - confirming → はい（実行）

    func testConfirmYesRunsBrewAndSucceeds() async {
        let (model, _, updater) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        model.runUpdate()
        XCTAssertEqual(model.phase, .running)
        await waitUntil { model.phase == .done }
        let runCount = await updater.runCount
        let repairCount = await updater.repairCount
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(repairCount, 0)
    }

    func testConfirmYesBrokenRunsRepair() async {
        let (model, _, updater) = makeModel(update: nil, broken: true, brewManaged: true)
        model.handleTap()
        model.runUpdate()
        await waitUntil { model.phase == .done }
        let repairCount = await updater.repairCount
        let runCount = await updater.runCount
        XCTAssertEqual(repairCount, 1)
        XCTAssertEqual(runCount, 0)
    }

    func testConfirmYesFailureGoesToFailed() async {
        let (model, _, _) = makeModel(
            update: releaseInfo, brewManaged: true,
            behavior: .fail("ダウンロードに失敗")
        )
        model.handleTap()
        model.runUpdate()
        await waitUntil { if case .failed = model.phase { return true } else { return false } }
        guard case .failed(let message) = model.phase else {
            return XCTFail("failed フェーズのはず")
        }
        XCTAssertTrue(message.contains("更新に失敗しました"))
        XCTAssertTrue(message.contains("ダウンロードに失敗"))
    }

    func testFailedTapRetriesFromConfirming() {
        let (model, _, _) = makeModel(
            update: releaseInfo, brewManaged: true,
            behavior: .fail("boom")
        )
        model.phase = .failed("更新に失敗しました: boom") // 実行失敗後の状態を再現
        model.handleTap()
        XCTAssertEqual(model.phase, .confirming)
    }

    // MARK: - confirming → いいえ（コピー確認）

    func testConfirmNoGoesToConfirmCopy() {
        let (model, _, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        model.declineUpdate()
        XCTAssertEqual(model.phase, .confirmCopy)
    }

    func testConfirmCopyYesCopiesCommandAndShowsCopied() {
        let (model, captures, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        model.declineUpdate()
        model.copyCommand()
        XCTAssertEqual(model.phase, .copied)
        XCTAssertEqual(captures.read(\.copied), ["brew update && brew upgrade --cask moost"])
    }

    func testConfirmCopyYesCopiesRepairCommandWhenBroken() {
        let (model, captures, _) = makeModel(update: nil, broken: true)
        model.handleTap()
        model.declineUpdate()
        model.copyCommand()
        XCTAssertEqual(captures.read(\.copied), ["brew reinstall --cask moost"])
    }

    func testCopiedRevertsToIdleAfterHold() async {
        let (model, _, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.copiedHoldDuration = 0.01
        model.handleTap()
        model.declineUpdate()
        model.copyCommand()
        XCTAssertEqual(model.phase, .copied)
        await waitUntil { model.phase == .idle }
    }

    func testConfirmCopyNoGoesToIdle() {
        let (model, _, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        model.declineUpdate()
        model.declineCopy()
        XCTAssertEqual(model.phase, .idle)
    }

    // MARK: - done / 再起動

    func testRestartNowCallsRestart() async {
        let (model, captures, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.handleTap()
        model.runUpdate()
        await waitUntil { model.phase == .done }
        model.restartNow()
        XCTAssertEqual(captures.read(\.restarted), 1)
    }

    func testRestartNowIgnoredUnlessDone() {
        let (model, captures, _) = makeModel(update: releaseInfo, brewManaged: true)
        model.restartNow()
        XCTAssertEqual(captures.read(\.restarted), 0)
    }

    // MARK: - エラーメッセージコピー

    func testCopyErrorMessageCopiesFailedText() {
        let (model, captures, _) = makeModel(
            update: releaseInfo, brewManaged: true,
            behavior: .fail("ネットワークエラー")
        )
        model.phase = .failed("更新に失敗しました: ネットワークエラー")
        model.copyErrorMessage()
        XCTAssertEqual(captures.read(\.copied),
                       ["更新に失敗しました: ネットワークエラー"])
    }

    // MARK: - 補助

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("条件がタイムアウトしました")
    }
}
