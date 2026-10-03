import SwiftUI
import MoostCore

/// セッション詳細（design.md 6.1-3）。
/// メタ情報 + 要約範囲セグメント（直近 N ラリー / 全体）+ 復帰動線。
/// 要約は native 対応済み（エンジン移植は MoostCore、バックグラウンド実行）。
struct SessionDetailScreen: View {
    let session: RecentSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "セッション詳細") {
                model.backToList(returningTo: .sessions)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.aiTitle ?? String(session.lastPrompt.prefix(80)))
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)

                    MetaPanel(
                        agentId: session.agentId,
                        projectPath: session.projectPath,
                        sessionId: session.sessionId,
                        updatedAt: session.updatedAt)

                    SummarySection(session: session)

                    Text("最後のあなたの発言")
                        .font(.system(size: 11, weight: .medium))
                    Text(session.lastPrompt)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
            }

            HStack {
                Button {
                    model.openNewMemo(for: session)
                } label: {
                    Label("このセッションをメモ", systemImage: "square.and.pencil")
                }
                Spacer()
                Button {
                    model.copyResumeCommand(agent: session.agentId,
                                            projectPath: session.projectPath,
                                            sessionId: session.sessionId)
                } label: {
                    Label("復帰コマンドをコピー", systemImage: "doc.on.doc")
                }
                Button {
                    model.openInTerminal(agent: session.agentId,
                                         projectPath: session.projectPath,
                                         sessionId: session.sessionId)
                } label: {
                    Label("ターミナルで開く", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
