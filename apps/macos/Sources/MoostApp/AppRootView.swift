import SwiftUI
import MoostCore

/// ルート画面。単一の状態変数（model.screen）を switch で切替える
/// （design.md 6.2 の遷移図と 1 対 1）。スタック型ナビゲーションは使わない。
struct AppRootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let toast = model.toast {
                ToastBanner(text: toast)
            }
            Group {
                switch model.screen {
                case .list:
                    ListScreen()
                case .newMemo(let session):
                    NewMemoScreen(session: session)
                case .editMemo(let memo):
                    EditMemoScreen(memo: memo)
                case .sessionDetail(let session):
                    SessionDetailScreen(session: session)
                case .summary(let session):
                    SummaryScreen(session: session)
                case .settings:
                    SettingsScreen()
                case .notes:
                    NotesScreen()
                }
            }
        }
        .frame(width: AppInfo.popoverSize.width, height: AppInfo.popoverSize.height)
    }
}

/// ポップオーバー内トースト。ダイアログは出さない（design.md 7 章【5】）。
struct ToastBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }
}

/// 画面見出し（appHeadline = 15pt semibold）。
struct ScreenHeader: View {
    let title: String
    var onBack: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if let onBack {
                Button("戻る", action: onBack)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// エージェントのバッジ（色は Flutter 側 root_screen.dart の _agentColor と同値）。
struct AgentBadge: View {
    let agentId: String

    /// エージェント識別子の色（Flutter 側 `_agentColor` と同値）。プロジェクト行の
    /// ターミナルアイコンなどにも使うため static で公開する。
    static func color(for agentId: String) -> Color {
        switch agentId {
        case ResumeCommand.claudeAgentId:
            return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255) // 0xFFD97757
        case ResumeCommand.codexAgentId:
            return Color(red: 0x68 / 255, green: 0x67 / 255, blue: 0xAA / 255) // 0xFF6867AA
        case ResumeCommand.piAgentId:
            return Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x9E / 255) // 0xFF2E7D9E
        default:
            return Color.secondary
        }
    }

    /// 表示用のエージェント名（要約ボタンのラベルにも使う）。
    static func displayName(for agentId: String) -> String {
        switch agentId {
        case ResumeCommand.claudeAgentId: return "Claude"
        case ResumeCommand.codexAgentId: return "Codex"
        case ResumeCommand.piAgentId: return "pi"
        default: return agentId
        }
    }

    private var label: String { Self.displayName(for: agentId) }

    private var color: Color { Self.color(for: agentId) }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}
