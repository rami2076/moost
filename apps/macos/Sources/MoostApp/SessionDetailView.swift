import SwiftUI
import MoostCore

/// セッション詳細（design.md 6.1-3）。
/// メタ情報 + 要約範囲セグメント（直近 N ラリー / 全体）+ 復帰動線。
/// 要約ボタンは次インクリメント（エンジン未移植のため無効 + 説明）。
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

                    Text("最後のあなたの発言")
                        .font(.system(size: 11, weight: .medium))
                    Text(session.lastPrompt)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    summarySection
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

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要約")
                .font(.system(size: 13, weight: .semibold))
            Picker("要約範囲", selection: $model.summaryScopeIsRecent) {
                Text("直近").tag(true)
                Text("全体").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("ラリー数: \(model.summaryRallies)")
                    .font(.system(size: 12))
                Spacer()
                Stepper("", value: Binding(
                    get: { model.summaryRallies },
                    set: { model.setSummaryRallies($0) }), in: 1...20, step: 1)
                .disabled(!model.summaryScopeIsRecent)
            }

            HStack(spacing: 8) {
                Button {
                    model.requestSummary(session)
                } label: {
                    Label("\(AgentBadge.displayName(for: session.agentId)) で要約する",
                          systemImage: "sparkles")
                }
                .disabled(model.isSummarizing)
                if model.isSummarizing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = model.summaryError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if !model.summaryText.isEmpty {
                Text(model.summaryText)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.top, 4)
    }
}
