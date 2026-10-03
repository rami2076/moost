import AppKit
import Combine
import Foundation
import SwiftUI
import MoostCore

/// ポップオーバー単一画面のステートマシンとデータ保持（design.md 6.2 / 6.3）。
/// 各画面はコールバックで遷移をモデルに依頼するだけで、画面状態を自分で書き換えない。
@MainActor
final class AppModel: ObservableObject {
    enum ListTab: Hashable {
        case sessions
        case memos
        case projects
    }

    enum Screen: Equatable {
        case list
        case newMemo(RecentSession)
        case editMemo(Memo)
        case sessionDetail(RecentSession)
        case settings
        case notes
    }

    // MARK: 画面状態（単一の状態変数 + switch）

    @Published var screen: Screen = .list
    @Published var tab: ListTab = .sessions

    // MARK: データ

    @Published private(set) var sessions: [RecentSession] = []
    @Published private(set) var memos: [Memo] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var settings = MoostCore.Settings()
    /// 登録解除のインライン確認中のプロジェクト（該当行だけ確認表示に置き換える）
    @Published var pendingDeleteProjectId: String?
    /// メモ一覧の行から削除ボタンが押されたメモ（該当行だけ確認表示に置き換える）。
    @Published var pendingDeleteMemoId: String?

    // MARK: フォーム下書き（画面遷移で破棄しない）

    @Published var draftTitle = ""
    @Published var draftTags = ""
    @Published var draftBody = ""
    @Published var editingMemoId: String?
    @Published var editTitle = ""
    @Published var editTags = ""
    @Published var editBody = ""
    /// 登録フォーム内のインレイン詳細（design.md 6.3-2。下書きを守る例外的な重ね表示）
    @Published var newMemoShowsDetail = false

    // MARK: 要約

    @Published var summaryScopeIsRecent = true
    @Published var summaryRallies = 1
    @Published var isSummarizing = false
    /// 最後に実行した要約の結果（成功時のみ）。画面を開き直すとリセットする。
    @Published var summaryText = ""
    /// 要約実行の失敗メッセージ。成功時は nil に戻す。
    @Published var summaryError: String?

    // MARK: その他 UI 状態

    @Published var toast: String?
    @Published var detectedClaudePath = ""
    @Published var autoLaunchEnabled = false
    @Published var deleteConfirmVisible = false

    private let memoStore: MemoStore
    private let settingsStore: SettingsStore
    private let projectStore: ProjectStore
    private let home: String
    private let terminalLauncher = TerminalLauncher()
    private var toastTask: Task<Void, Never>?
    /// 一覧・メモの読み込みタスク（最新 1 本だけ生かす）
    private var refreshTask: Task<Void, Never>?
    /// claude パス検出タスク（zsh 起動を伴うため必ずバックグラウンド）
    private var detectTask: Task<Void, Never>?
    /// 要約結果のメモリキャッシュ（sessionId × scope × ラリー数）
    private let summaryCache = SummaryCache()

    init(memoStore: MemoStore, settingsStore: SettingsStore,
         projectStore: ProjectStore, home: String) {
        self.memoStore = memoStore
        self.settingsStore = settingsStore
        self.projectStore = projectStore
        self.home = home
    }

    static func defaultApp() -> AppModel {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return AppModel(memoStore: MemoStore.defaultLocation(),
                        settingsStore: SettingsStore.defaultLocation(),
                        projectStore: ProjectStore.defaultLocation(),
                        home: home)
    }

    /// 初回起動（v1 → v2 移行を含む）。
    func bootstrap() {
        do {
            _ = try DataMigration.migrateIfNeeded(homeDirectoryPath: home)
        } catch {
            showToast("v1 からの移行に失敗しました: \(error.localizedDescription)")
        }
        loadSettings()
        reloadAutoLaunchStatus()
        detectClaudePath()
        refresh()
    }

    /// ポップオーバーを開いたとき・タブを切り替えたとき・フォームから戻ったときに
    /// 呼ぶ（design.md 6.1「手動リロード不要。開きっぱなしの間は更新されない」）。
    /// UI をブロックしないよう、ファイル走査はバックグラウンドで行い
    /// 完了後に published を更新する。
    func refresh() {
        refreshTask?.cancel()
        let home = self.home
        let memoFileURL = memoStore.file
        let projectFileURL = projectStore.file
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.loadSettings()
            summaryRallies = self.settings.summaryRallyCount
            let limit = self.settings.recentSessionLimit
            if Task.isCancelled { return }

            let sessions = await Task.detached(priority: .userInitiated) {
                SessionAggregator.recentSessions(homeDirectory: home, limit: limit)
            }.value
            guard !Task.isCancelled else { return }
            self.sessions = sessions

            let memos = await Task.detached(priority: .userInitiated) {
                (try? MemoStore(file: memoFileURL).load()) ?? []
            }.value
            guard !Task.isCancelled else { return }
            self.memos = memos

            let projects = await Task.detached(priority: .userInitiated) {
                (try? ProjectStore(file: projectFileURL).load()) ?? []
            }.value
            guard !Task.isCancelled else { return }
            self.projects = projects
        }
    }

    // MARK: - 読み込み

    private func loadSettings() {
        do {
            settings = try settingsStore.load()
        } catch {
            showToast("設定を読み込めませんでした: \(error.localizedDescription)")
        }
    }

    /// claude パス検出（zsh 起動を伴い最大 1 秒超のため必ず非同期）。
    /// 起動時と claudePath 設定変更時のみ呼ぶ。
    func detectClaudePath() {
        detectTask?.cancel()
        let override = settings.claudePath
        detectTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                AgentPathDetect.claude(override: override)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.detectedClaudePath = found
                ?? "見つかりません（要約機能は claude コマンドが必要）"
        }
    }

    // MARK: - 画面遷移（design.md 6.3-3: 遷移はルートに集約）

    func openNewMemo(for session: RecentSession) {
        draftTitle = session.aiTitle ?? String(session.lastPrompt.prefix(80))
        draftTags = ""
        draftBody = ""
        newMemoShowsDetail = false
        screen = .newMemo(session)
    }

    func openEditMemo(_ memo: Memo) {
        editingMemoId = memo.id
        editTitle = memo.title
        editTags = memo.tags.joined(separator: ", ")
        editBody = memo.body
        deleteConfirmVisible = false
        screen = .editMemo(memo)
    }

    func openSessionDetail(_ session: RecentSession) {
        summaryScopeIsRecent = true
        isSummarizing = false
        summaryText = ""
        summaryError = nil
        screen = .sessionDetail(session)
    }

    func openSettings() { screen = .settings }
    func openNotes() { screen = .notes }
    func backToList(returningTo tab: ListTab) {
        screen = .list
        self.tab = tab
        refresh()
    }

    func switchTab(_ tab: ListTab) {
        self.tab = tab
        refresh()
    }

    // MARK: - メモ CRUD

    func saveNewMemo(for session: RecentSession) {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showToast("タイトルを入力してください")
            return
        }
        let memo = Memo(
            id: UUID().uuidString.lowercased(),
            agent: session.agentId,
            sessionId: session.sessionId,
            title: title,
            tags: parseTags(draftTags),
            body: draftBody,
            projectPath: session.projectPath,
            createdAt: Date(),
            updatedAt: Date())
        do {
            try memoStore.add(memo)
            // refresh() は全セッション集計（約 0.7 秒）を含み重いため、
            // メモ一覧だけをローカル即時更新して一覧へ戻す（ラグ解消）。
            memos.append(memo)
            showToast("メモを保存しました")
            screen = .list
            tab = .memos // 登録したメモを確認できるように（6.3-1）
        } catch {
            showToast("保存に失敗しました: \(error.localizedDescription)")
        }
    }

    func cancelNewMemo() {
        backToList(returningTo: .sessions) // 入口だった画面へ（6.3-1）
    }

    func updateMemo(_ memo: Memo) {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showToast("タイトルを入力してください")
            return
        }
        do {
            _ = try memoStore.update(memo.id, title: title,
                                     tags: parseTags(editTags), body: editBody)
            // refresh() は全セッション集計を含み重いため、メモ一覧をローカル即時更新する。
            let updated = memo.updateUserFields(
                title: title, tags: parseTags(editTags), body: editBody, updatedAt: Date())
            if let index = memos.firstIndex(where: { $0.id == memo.id }) {
                memos[index] = updated
            } else {
                memos.append(updated)
            }
            showToast("メモを更新しました")
            screen = .list
            tab = .memos
        } catch {
            showToast("更新に失敗しました: \(error.localizedDescription)")
        }
    }

    func deleteMemo(_ memo: Memo) {
        do {
            _ = try memoStore.delete(memo.id)
            // v1（Flutter 版）と同じく成功時はトーストを出さない。
            // 行が消えるだけで十分（ユーザー要望: 削除ボタンで即座に消える）。
            // refresh() は全セッション集計を含み重いため、メモ一覧だけを即時更新する。
            memos.removeAll { $0.id == memo.id }
            screen = .list
            tab = .memos
        } catch {
            showToast("削除に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - メモ削除（一覧行の削除ボタン → インライン確認行。v1 互換）

    /// メモ一覧の行から削除ボタンが押された。該当行だけ確認表示に置き換える。
    func requestDeleteMemo(_ memo: Memo) {
        pendingDeleteMemoId = memo.id
    }

    func cancelDeleteMemo() {
        pendingDeleteMemoId = nil
    }

    func confirmDeleteMemo(_ memo: Memo) {
        pendingDeleteMemoId = nil
        deleteMemo(memo)
    }

    // MARK: - 設定

    func saveSettings(_ updated: MoostCore.Settings) {
        do {
            try settingsStore.save(updated)
            settings = updated
            showToast("設定を保存しました")
            // 表示件数・ターミナルを反映（非同期）
            refresh()
            detectClaudePath()
        } catch {
            showToast("設定を保存できませんでした: \(error.localizedDescription)")
        }
    }

    /// 要約対象のラリー数。設定画面に出さないが永続化する（design.md 6.6）。
    func setSummaryRallies(_ count: Int) {
        summaryRallies = count
        var updated = settings
        updated.summaryRallyCount = count
        settings = updated
        do {
            try settingsStore.save(updated)
        } catch {
            showToast("ラリー数の保存に失敗しました: \(error.localizedDescription)")
        }
    }

    func setAutoLaunch(_ enabled: Bool) {
        do {
            try AutoLaunchService.setEnabled(enabled)
            autoLaunchEnabled = enabled
        } catch {
            showToast("ログイン時自動起動の変更に失敗しました: \(error.localizedDescription)")
        }
        reloadAutoLaunchStatus()
    }

    /// OS の実状態を再読込（SMAppService.status は XPC を伴い遅いため、
    /// 起動時とトグル操作時のみ。一覧更新のたびには呼ばない）。
    private func reloadAutoLaunchStatus() {
        autoLaunchEnabled = AutoLaunchService.isEnabled()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 復帰・コピー（spec G1 / G2 をこの層から使う）

    private func resumeCommand(agent: String, projectPath: String, sessionId: String) -> String? {
        ResumeCommand.resume(agent: agent, projectPath: projectPath, sessionId: sessionId,
                             provider: settings.piProvider, model: settings.piModel)
    }

    func copyResumeCommand(agent: String, projectPath: String, sessionId: String) {
        guard let command = resumeCommand(agent: agent, projectPath: projectPath, sessionId: sessionId)
        else {
            showToast("不明なエージェントです: \(agent)")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        showToast("復帰コマンドをコピーしました")
    }

    func openInTerminal(agent: String, projectPath: String, sessionId: String) {
        guard let command = resumeCommand(agent: agent, projectPath: projectPath, sessionId: sessionId)
        else {
            showToast("不明なエージェントです: \(agent)")
            return
        }
        launchTerminalCommand(command: command)
    }

    /// osascript によるターミナル起動をバックグラウンドで実行する。
    /// iTerm2/Terminal.app が未起動の場合、Apple Events の送信が起動完了まで
    /// 数秒ブロックするため、メインスレッドで実行するとビーチボールになる。
    /// 起動中 → 成功/失敗のトーストでフィードバックする。
    private func launchTerminalCommand(command: String) {
        let terminalApp = settings.terminalApp
        showToast("ターミナルを起動しています…")
        Task { @MainActor in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try TerminalLauncher().launch(settingValue: terminalApp, command: command)
                }.value
                showToast("ターミナルを開きました")
            } catch {
                showToast("ターミナルを起動できませんでした: \(error.localizedDescription)")
            }
        }
    }

    /// メモからの復帰動線（メモは復帰情報を自己完結で持つ）。
    func resumeFromMemo(_ memo: Memo) {
        openInTerminal(agent: memo.agent, projectPath: memo.projectPath,
                       sessionId: memo.sessionId)
    }

    // MARK: - 登録プロジェクト（v1 のプロジェクトタブ相当）

    /// フォルダ選択ダイアログを開き、選ばれたディレクトリを登録プロジェクトとして保存する。
    /// キャンセル時は何も変更しない（Flutter 版の `_registerProject` と同じ挙動）。
    func registerProject() {
        let panel = NSOpenPanel()
        panel.title = "登録プロジェクトの選択"
        panel.message = "新規セッションを開始したいディレクトリを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "登録"
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        let project = Project(id: UUID().uuidString, projectPath: path, createdAt: Date())
        saveProjects(adding: project)
        // refresh() は全セッション集計を含み重いため、プロジェクト一覧だけを
        // ローカル即時更新する（メモ CRUD と同じラグ対策）。
        projects.append(project)
        showToast("プロジェクトを登録しました")
    }

    func requestDeleteProject(_ project: Project) {
        pendingDeleteProjectId = project.id
    }

    func cancelDeleteProject() {
        pendingDeleteProjectId = nil
    }

    func confirmDeleteProject(_ project: Project) {
        pendingDeleteProjectId = nil
        saveProjects(removing: project.id)
        // refresh() は全セッション集計を含み重いため、プロジェクト一覧だけを
        // ローカル即時更新する（メモ削除と同じく成功トーストは出さない）。
        projects.removeAll { $0.id == project.id }
    }

    private func saveProjects(adding newProject: Project? = nil, removing id: String? = nil) {
        do {
            var list = try projectStore.load()
            if let newProject {
                list.append(newProject)
            }
            if let id {
                list.removeAll { $0.id == id }
            }
            try projectStore.save(list)
        } catch {
            showToast("プロジェクトの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    /// 登録プロジェクトから新規セッションを開始する（ADR-004: sessionId は取らない）。
    func launchNewSession(agent: String, projectPath: String) {
        guard let command = ResumeCommand.newSession(
            agent: agent, projectPath: projectPath,
            provider: settings.piProvider, model: settings.piModel)
        else {
            showToast("不明なエージェントです: \(agent)")
            return
        }
        launchTerminalCommand(command: command)
    }

    // MARK: - 要約（design.md 5 / 6.6 / 6.1）

    /// design.md 6.1 の要約ボタン。
    /// エージェント別に transcript を抽出し、ヘッドレス CLI で要約する
    /// （pi は抽出テキストをそのまま要約として扱う）。
    /// 実行結果は SummaryCache にキャッシュし、同じセッション詳細を
    /// 開き直したときに再実行しない。
    func requestSummary(_ session: RecentSession) {
        let cached = summaryCache.get(
            session.sessionId,
            scope: summaryScopeIsRecent ? .recent : .full,
            rallies: summaryRallies)
        if let cached {
            summaryText = cached
            summaryError = nil
            return
        }

        isSummarizing = true
        summaryError = nil
        let summarizer = SessionSummarizer(home: home, claudePathOverride: settings.claudePath)
        let scope: SummaryScope = summaryScopeIsRecent ? .recent : .full
        let rallies = summaryRallies
        Task { [weak self] in
            do {
                // 要約はファイル走査 + サブプロセス起動を伴うため main をブロックしない
                let summary = try await Task.detached(priority: .userInitiated) {
                    try await summarizer.summarize(
                        session: session, scope: scope, rallies: rallies)
                }.value
                guard let self else { return }
                self.summaryCache.put(
                    session.sessionId, scope: scope, rallies: rallies, summary: summary)
                self.summaryText = summary
                self.summaryError = nil
                self.isSummarizing = false
            } catch {
                guard let self else { return }
                let message = (error as? SummarizeError)?.message
                    ?? error.localizedDescription
                self.summaryText = ""
                self.summaryError = message
                self.isSummarizing = false
            }
        }
    }

    // MARK: - トースト

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
