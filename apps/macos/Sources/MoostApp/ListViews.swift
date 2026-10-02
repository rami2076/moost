import SwiftUI
import MoostCore

/// ルートの一覧画面（直近セッション / メモ一覧の 2 タブ + フッター）。
/// 行クリック → メモ登録（セッション）/ メモ編集（メモ）。詳細・コピーのアイコン付き。
struct ListScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("タブ", selection: Binding(
                get: { model.tab },
                set: { model.switchTab($0) })) {
                Text("直近セッション").tag(AppModel.ListTab.sessions)
                Text("メモ一覧").tag(AppModel.ListTab.memos)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch model.tab {
            case .sessions:
                sessionList
            case .memos:
                memoList
            }

            footer
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.sessions, id: \.sessionId) { session in
                    SessionRow(session: session)
                        .onTapGesture { model.openNewMemo(for: session) }
                    Divider()
                }
                if model.sessions.isEmpty {
                    EmptyHint(text: "直近セッションがありません。\nclaude / codex / pi で作業すると表示されます。")
                }
            }
        }
    }

    private var memoList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.memos, id: \.id) { memo in
                    MemoRow(memo: memo)
                        .onTapGesture { model.openEditMemo(memo) }
                    Divider()
                }
                if model.memos.isEmpty {
                    EmptyHint(text: "メモがありません。\n直近セッションから登録できます。")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.openSettings()
            } label: {
                Label("設定", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            Button {
                model.openNotes()
            } label: {
                Label("注意", systemImage: "info.circle")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                model.quit()
            } label: {
                Label("終了", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}

struct SessionRow: View {
    let session: RecentSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.aiTitle ?? String(session.lastPrompt.prefix(80)))
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.copyResumeCommand(agent: session.agentId,
                                            projectPath: session.projectPath,
                                            sessionId: session.sessionId)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("復帰コマンドをコピー")
                Button {
                    model.openSessionDetail(session)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("セッション詳細")
            }
            HStack(spacing: 6) {
                AgentBadge(agentId: session.agentId)
                Text(session.projectPath.isEmpty ? "(パス不明)" : session.projectPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(AppFormat.dateTime(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct MemoRow: View {
    let memo: Memo
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(memo.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.copyResumeCommand(agent: memo.agent,
                                            projectPath: memo.projectPath,
                                            sessionId: memo.sessionId)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("復帰コマンドをコピー")
            }
            HStack(spacing: 6) {
                AgentBadge(agentId: memo.agent)
                if !memo.tags.isEmpty {
                    Text(memo.tags.joined(separator: " #"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(memo.projectPath.isEmpty ? "(パス不明)" : memo.projectPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(AppFormat.dateTime(memo.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
