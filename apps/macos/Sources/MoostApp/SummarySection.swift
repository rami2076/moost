import SwiftUI
import MoostCore

/// 要約セクション（design.md 6.3-2 / 6.1-3）。
/// セッション詳細画面とメモ登録フォーム内のインライン詳細で共用する。
struct SummarySection: View {
    let session: RecentSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要約")
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: $model.summaryScopeIsRecent) {
                Text("直近").tag(true)
                Text("全体").tag(false)
            }
            .pickerStyle(.segmented)

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
