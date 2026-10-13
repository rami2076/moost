import Combine
import Foundation

/// フッターの更新ボタンの状態機械（Flutter 版 `_UpdateButtonState` の native 移植）。
///
/// 遷移（root_screen.dart の実装に対応）:
///
/// ```text
/// idle ──タップ(brew 管理 or 破損)──▶ confirming
/// idle ──タップ(手動導入)───────────▶ リリースページを開く（idle のまま）
/// confirming ──はい──▶ running ──成功──▶ done（再起動）
///              │              └──失敗──▶ failed(メッセージ)
///              └──いいえ──▶ confirmCopy ──はい──▶ copied ──3秒後──▶ idle
///                                      └──いいえ──▶ idle
/// failed ──再試行タップ──▶ confirming
/// done ──再起動タップ──▶ アプリ再起動
/// ```
///
/// 破損時（installBroken）は文言が「修復」になり、実行内容が
/// `brew reinstall --cask moost` に切り替わる。
@MainActor
final class UpdateButtonModel: ObservableObject {
    enum Phase: Equatable, Hashable {
        case idle
        case confirming
        case confirmCopy
        case copied
        case running
        case done
        case failed(String)
    }

    /// フッターの他ボタンを隠すほど幅を取るフェーズ（Flutter の `_expandedPhases`）。
    static let expandedPhases: Set<Phase> = [.confirming, .confirmCopy, .copied, .running]

    @Published internal(set) var phase: Phase = .idle

    let update: UpdateInfo?
    let isInstallBroken: Bool
    let isBrewManaged: () -> Bool
    let openURL: (URL) -> Void
    let copyText: (String) -> Void
    let updater: BrewUpdating
    let restart: () -> Void
    /// コピー済み表示を idle に戻すまでの秒数（Flutter のタイマーに相当。テストで短縮可能）。
    var copiedHoldDuration: TimeInterval = 3

    init(
        update: UpdateInfo?,
        isInstallBroken: Bool,
        isBrewManaged: @escaping () -> Bool,
        openURL: @escaping (URL) -> Void,
        copyText: @escaping (String) -> Void,
        updater: BrewUpdating,
        restart: @escaping () -> Void
    ) {
        self.update = update
        self.isInstallBroken = isInstallBroken
        self.isBrewManaged = isBrewManaged
        self.openURL = openURL
        self.copyText = copyText
        self.updater = updater
        self.restart = restart
    }

    /// コピーするコマンド（Flutter でコピーされる文字列と同一）。
    var commandToCopy: String {
        isInstallBroken ? "brew reinstall --cask moost"
                        : "brew update && brew upgrade --cask moost"
    }

    var isExpanded: Bool {
        Self.expandedPhases.contains(phase)
    }

    // MARK: - ユーザー操作

    /// idle / failed のタップ。
    func handleTap() {
        switch phase {
        case .failed:
            // 失敗からの再試行は確認から（Flutter と同じ）。
            phase = .confirming
        case .idle:
            if isInstallBroken || isBrewManaged() {
                phase = .confirming
            } else if let update {
                // 手動導入（brew 管理外）はリリースページを開くだけ。
                openURL(update.releaseURL)
            }
        default:
            break
        }
    }

    /// confirming の「はい」: brew 更新（または修復）を実行。
    func runUpdate() {
        guard phase == .confirming else { return }
        phase = .running
        let updater = self.updater
        let broken = isInstallBroken
        Task { @MainActor in
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    if broken {
                        try await updater.repair()
                    } else {
                        try await updater.run()
                    }
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success:
                phase = .done
            case .failure(let error):
                phase = .failed(errorMessage(for: error))
            }
        }
    }

    /// confirming の「いいえ」: コマンドコピーの確認へ。
    func declineUpdate() {
        guard phase == .confirming else { return }
        phase = .confirmCopy
    }

    /// confirmCopy の「はい」: クリップボードにコマンドをコピー。
    func copyCommand() {
        guard phase == .confirmCopy else { return }
        copyText(commandToCopy)
        phase = .copied
        let hold = copiedHoldDuration
        Task { [weak self] in
            if hold > 0 { try? await Task.sleep(for: .seconds(hold)) }
            guard !Task.isCancelled, let self, self.phase == .copied else { return }
            self.phase = .idle
        }
    }

    /// confirmCopy の「いいえ」: idle へ。
    func declineCopy() {
        guard phase == .confirmCopy else { return }
        phase = .idle
    }

    /// done の「再起動」。
    func restartNow() {
        guard phase == .done else { return }
        restart()
    }

    /// failed の「エラーメッセージをコピー」。
    func copyErrorMessage() {
        guard case .failed(let message) = phase else { return }
        copyText(message)
    }

    private func errorMessage(for error: Error) -> String {
        let base = isInstallBroken ? "修復に失敗しました: " : "更新に失敗しました: "
        let detail = (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription
        return base + detail
    }
}
