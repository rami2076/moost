import AppKit
import SwiftUI

/// フッターの更新ボタン（Flutter 版 `_UpdateButton` の native 移植）。
///
/// ボタンは「新しいバージョンが利用可能」または「インストール破損」のときだけ
/// 表示される（親の ListScreen が model.updateInfo / model.installBroken で制御）。
/// 状態遷移と brew 実行は [UpdateButtonModel]（Dart の `_UpdateButtonState` 相当）に
/// 委譲し、この View は表示と入力を担うだけ。
///
/// ダイアログは使わない（design.md 7章【5】: モーダルはポップオーバーを閉じてしまう）
/// ため、確認はインラインのピル表示（Flutter と同様の小さい はい/いいえ）で行う。
struct UpdateButtonView: View {
    @StateObject private var model: UpdateButtonModel

    init(
        update: UpdateInfo?,
        isInstallBroken: Bool,
        isBrewManaged: @escaping () -> Bool = { InstallHealthChecker.isBrewManaged }
    ) {
        _model = StateObject(wrappedValue: UpdateButtonModel(
            update: update,
            isInstallBroken: isInstallBroken,
            isBrewManaged: isBrewManaged,
            openURL: { url in NSWorkspace.shared.open(url) },
            copyText: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            updater: BrewUpdater(),
            restart: { UpdateButtonView.restartApp() }
        ))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                idleButton
            case .confirming:
                pill(question: model.isInstallBroken
                    ? "アプリの状態を修復しますか?"
                    : "アップデートしますか?",
                     onYes: { model.runUpdate() },
                     onNo: { model.declineUpdate() })
            case .confirmCopy:
                pill(question: model.isInstallBroken
                    ? "修復コマンドをコピーしますか?"
                    : "アップデートコマンドをコピーしますか?",
                     onYes: { model.copyCommand() },
                     onNo: { model.declineCopy() })
            case .copied:
                pill(icon: "checkmark.circle.fill", tint: .green,
                     text: "コマンドをコピーしました")
            case .running:
                pill(icon: "hourglass", tint: .secondary,
                     text: model.isInstallBroken ? "修復中…" : "更新中…",
                     spinner: true)
            case .done:
                Button {
                    model.restartNow()
                } label: {
                    Label("再起動", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("新しいバージョンを起動します")
            case .failed(let message):
                failedPill(message: message)
            }
        }
    }

    // MARK: - 各フェーズの表示

    private var idleButton: some View {
        Button {
            model.handleTap()
        } label: {
            Label(
                model.isInstallBroken ? "修復" : "アップデート",
                systemImage: model.isInstallBroken ? "exclamationmark.triangle" : "arrow.up.circle"
            )
        }
        .buttonStyle(.borderless)
        .help(model.isInstallBroken
            ? "アプリの状態を修復できます"
            : "\(model.update?.version ?? "") が利用可能")
    }

    /// はい/いいえ確認（confirming / confirmCopy 共通）。
    private func pill(question: String, onYes: @escaping () -> Void,
                      onNo: @escaping () -> Void) -> some View {
        pill {
            Text(question)
                .lineLimit(1)
            Button("はい", action: onYes)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("いいえ", action: onNo)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }

    /// 状態表示（copied / running / エラー以外）。
    private func pill(icon: String, tint: Color, text: String, spinner: Bool = false) -> some View {
        pill {
            if spinner {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Text(text)
                .lineLimit(1)
        }
    }

    private func failedPill(message: String) -> some View {
        pill {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Button {
                model.handleTap()
            } label: {
                Text(model.isInstallBroken ? "修復" : "アップデート")
            }
            .buttonStyle(.borderless)
            .help((model.isInstallBroken ? "修復に失敗しました: " : "更新に失敗しました: ") + message)
            Button {
                model.copyErrorMessage()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("エラーメッセージをコピー")
        }
    }

    private func pill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }

    /// アプリを再起動する（Flutter の `restartApp`: open で起動してから終了）。
    static func restartApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Moost.app"]
        try? process.run()
        NSApp.terminate(nil)
    }
}
