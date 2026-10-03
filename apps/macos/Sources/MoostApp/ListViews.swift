import SwiftUI
import MoostCore

/// ビューのグローバル座標を **AppKit 座標（左下原点）** で報告する NSViewRepresentable。
/// SwiftUI の geo.frame(in: .global) は左上原点で NSOpenPanel.frame / NSEvent.mouseLocation
/// （左下原点）と混同しやすく、そのまま使うと y が反転する（2026-10-03 実測）。
/// そのため NSView の convertToScreen で正確な AppKit グローバル座標を取得する。
struct ScreenPointReporter: NSViewRepresentable {
    let onReport: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            let inWindow = v.convert(v.bounds, to: nil)
            onReport(window.convertToScreen(inWindow))
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// ルートの一覧画面（直近セッション / メモ一覧 / 登録プロジェクトの 3 タブ + フッター）。
/// 行クリック → メモ登録（セッション）/ メモ編集（メモ）。詳細・コピーのアイコン付き。
/// プロジェクトタブは v1（Flutter 版）のプロジェクト一覧に相当（design.md 6.1 では
/// 2 タブだったが、v1 との機能差を埋めるため 2026-10-02 に 3 タブ化）。
struct ListScreen: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("タブ", selection: Binding(
                get: { model.tab },
                set: { model.switchTab($0) })) {
                Text("セッション").tag(AppModel.ListTab.sessions)
                Text("メモ").tag(AppModel.ListTab.memos)
                Text("プロジェクト").tag(AppModel.ListTab.projects)
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
            case .projects:
                projectList
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
                    if model.pendingDeleteMemoId == memo.id {
                        MemoDeleteConfirmRow(memo: memo)
                    } else {
                        MemoRow(memo: memo)
                    }
                    Divider()
                }
                if model.memos.isEmpty {
                    EmptyHint(text: "メモがありません。\n直近セッションから登録できます。")
                }
            }
        }
    }

    private var projectList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    model.requestRegisterProject()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("ディレクトリを登録")
                .background(
                    ScreenPointReporter { frame in
                        model.projectAddButtonFrame = frame
                    }
                )
                Text("登録したディレクトリからエージェント別に新規セッションを開始できます")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.projects, id: \.id) { project in
                        if model.pendingDeleteProjectId == project.id {
                            ProjectDeleteConfirmRow(project: project)
                        } else {
                            ProjectRow(project: project)
                        }
                        Divider()
                    }
                    if model.projects.isEmpty {
                        EmptyHint(text: "登録プロジェクトがありません。\n右上のフォルダアイコンから登録できます。")
                    }
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
                    model.openInTerminal(agent: session.agentId,
                                         projectPath: session.projectPath,
                                         sessionId: session.sessionId)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("ターミナルで再開")
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
                    model.resumeFromMemo(memo)
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("ターミナルで再開")
                Button {
                    model.copyResumeCommand(agent: memo.agent,
                                            projectPath: memo.projectPath,
                                            sessionId: memo.sessionId)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("復帰コマンドをコピー")
                Button {
                    model.requestDeleteMemo(memo)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("削除")
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

/// 登録プロジェクトの行（v1 の `_ProjectList` 相当）。
/// 各エージェントのターミナルアイコン（新規セッション開始）と登録解除ボタンを持つ。
struct ProjectRow: View {
    let project: Project
    @EnvironmentObject var model: AppModel

    private let agents = [
        (ResumeCommand.claudeAgentId, "Claude"),
        (ResumeCommand.codexAgentId, "Codex"),
        (ResumeCommand.piAgentId, "pi"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.displayName)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                ForEach(agents, id: \.0) { agent in
                    Button {
                        model.launchNewSession(agent: agent.0, projectPath: project.projectPath)
                    } label: {
                        Image(systemName: "terminal")
                            .foregroundStyle(AgentBadge.color(for: agent.0))
                    }
                    .buttonStyle(.borderless)
                    .help("\(agent.1) で新規セッションを開始")
                }
                Button {
                    model.requestDeleteProject(project)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("登録を解除")
            }
            HStack(spacing: 6) {
                Text(project.projectPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("登録: " + AppFormat.dateTime(project.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// 登録解除のインライン確認行（メモ一覧の確認行と同じ体裁）。
struct ProjectDeleteConfirmRow: View {
    let project: Project
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("「\(project.displayName)」の登録を解除しますか？")
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Button("キャンセル") { model.cancelDeleteProject() }
                .buttonStyle(.borderless)
            Button("削除") { model.confirmDeleteProject(project) }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// メモ一覧の行から削除ボタンが押されたときのインライン確認行（v1 互換）。
struct MemoDeleteConfirmRow: View {
    let memo: Memo
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("このメモを削除しますか？")
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Button("キャンセル") { model.cancelDeleteMemo() }
                .buttonStyle(.borderless)
            Button("削除") { model.confirmDeleteMemo(memo) }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
