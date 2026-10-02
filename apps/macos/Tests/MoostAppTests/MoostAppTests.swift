import XCTest
import MoostCore
@testable import MoostApp

/// AppModel の状態遷移フローのテスト（design.md 6.3 のステートマシン）。
/// ストアは一時ディレクトリのファイルに注入し、実ホームディレクトリには
/// 一切触れない（bootstrap は DataMigration / SMAppService / zsh 検出を
/// 伴うため呼ばない。refresh はファイル走査のみで軽い）。
///
/// 注意: AppModel は @MainActor。メソッドは @MainActor で実行する。
/// XCTest の setUp/tearDown は nonisolated で呼ばれる（main thread で直列
/// 実行される）ため、ストレージは nonisolated(unsafe) で持つ。
/// refresh() 内部の Task 完了はポーリングで待つ。
@MainActor
final class MoostAppTests: XCTestCase {
    private nonisolated(unsafe) var tempDir: URL!
    private nonisolated(unsafe) var home: String!
    private nonisolated(unsafe) var memoStore: MemoStore!
    private nonisolated(unsafe) var settingsStore: SettingsStore!
    private nonisolated(unsafe) var projectStore: ProjectStore!

    private nonisolated var memoFile: URL { tempDir.appendingPathComponent("memos.json") }
    private nonisolated var settingsFile: URL { tempDir.appendingPathComponent("settings.json") }
    private nonisolated var projectFile: URL { tempDir.appendingPathComponent("projects.json") }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moost_appmodel_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        home = tempDir.path
        memoStore = MemoStore(file: memoFile)
        settingsStore = SettingsStore(file: settingsFile)
        projectStore = ProjectStore(file: projectFile)
        // セッションスキャン先を temp ホームに限定（実ホームを走査しない）
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(".moost/v2", isDirectory: true),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeModel() -> AppModel {
        AppModel(memoStore: memoStore, settingsStore: settingsStore,
                 projectStore: projectStore, home: home)
    }

    /// refresh() の非同期完了を待つ（ファイル走査 + ストア読み込み）。
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool,
                           timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s", file: file, line: line)
    }

    private func sampleSession(agentId: String = "pi") -> RecentSession {
        RecentSession(
            agentId: agentId, sessionId: "sess-\(UUID().uuidString)",
            projectPath: "", lastPrompt: "テスト用の最終プロンプト",
            updatedAt: Date(), aiTitle: "テストセッション")
    }

    // MARK: - メモ CRUD フロー

    func test_memo_add_save_round_trip() async throws {
        let model = makeModel()
        let session = sampleSession()

        model.openNewMemo(for: session)
        XCTAssertEqual(model.screen, .newMemo(session))

        model.draftTitle = " 振り返りメモ  "
        model.draftTags = " 検証, テスト "
        model.draftBody = "本文です"
        model.saveNewMemo(for: session)

        XCTAssertEqual(model.screen, .list)
        XCTAssertEqual(model.tab, .memos)

        let saved = try memoStore.load()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].title, "振り返りメモ")          // trim
        XCTAssertEqual(saved[0].tags, ["検証", "テスト"])        // 分割 + trim
        XCTAssertEqual(saved[0].body, "本文です")
        XCTAssertEqual(saved[0].sessionId, session.sessionId)

        await waitUntil { model.memos.count == 1 }
        XCTAssertEqual(model.memos[0].title, "振り返りメモ")
    }

    func test_memo_empty_title_is_not_saved() async throws {
        let model = makeModel()
        let session = sampleSession()

        model.openNewMemo(for: session)
        model.draftTitle = "   "
        model.saveNewMemo(for: session)

        XCTAssertEqual(try memoStore.load().count, 0)
        XCTAssertNotNil(model.toast) // 「タイトルを入力してください」
        // 画面はフォームのまま
        XCTAssertEqual(model.screen, .newMemo(session))
    }

    func test_memo_cancel_discards_without_saving() async throws {
        let model = makeModel()
        let session = sampleSession()

        model.openNewMemo(for: session)
        model.draftTitle = "下書き"
        model.cancelNewMemo()

        XCTAssertEqual(model.screen, .list)
        XCTAssertEqual(try memoStore.load().count, 0)
    }

    func test_memo_edit_updates_user_fields() async throws {
        let model = makeModel()
        let session = sampleSession()
        model.openNewMemo(for: session)
        model.draftTitle = "元タイトル"
        model.saveNewMemo(for: session)
        var memo = try memoStore.load()[0]

        model.openEditMemo(memo)
        model.editTitle = "更新タイトル"
        model.editTags = "新タグ"
        model.editBody = "更新本文"
        model.updateMemo(memo)

        memo = try memoStore.load()[0]
        XCTAssertEqual(memo.title, "更新タイトル")
        XCTAssertEqual(memo.tags, ["新タグ"])
        XCTAssertEqual(memo.body, "更新本文")
        XCTAssertEqual(model.screen, .list)
    }

    func test_memo_delete_removes_from_file() async throws {
        let model = makeModel()
        let session = sampleSession()
        model.openNewMemo(for: session)
        model.draftTitle = "消すメモ"
        model.saveNewMemo(for: session)
        let memo = try memoStore.load()[0]

        model.deleteMemo(memo)
        XCTAssertEqual(try memoStore.load().count, 0)
        XCTAssertEqual(model.screen, .list)
    }

    // MARK: - 読み込み

    func test_refresh_loads_projects_and_settings() async throws {
        // プロジェクト + 設定を事前にファイルへ
        try projectStore.save([
            Project(id: "p1", projectPath: "/work/my-project", createdAt: Date()),
            Project(id: "p2", projectPath: "/work/other", createdAt: Date()),
        ])
        var settings = Settings()
        settings.recentSessionLimit = 5
        settings.summaryRallyCount = 3
        try settingsStore.save(settings)

        let model = makeModel()
        model.refresh()

        await waitUntil { model.projects.count == 2 }
        XCTAssertEqual(model.projects[0].displayName, "my-project")
        XCTAssertEqual(model.settings.recentSessionLimit, 5)
        XCTAssertEqual(model.summaryRallies, 3)
        XCTAssertEqual(model.tab, .sessions)
    }

    // MARK: - 要約（pi 経路: 抽出テキストをそのまま返す）

    func test_pi_summary_populates_summary_text() async throws {
        // pi セッションの JSONL を temp ホームに用意する
        let piDir = tempDir.appendingPathComponent(".pi/agent/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: piDir, withIntermediateDirectories: true)
        let sessionId = "sess-summary-1"
        let lines = [
            "{\"type\":\"session\",\"version\":2,\"id\":\"\(sessionId)\","
                + "\"timestamp\":\"2026-03-01T00:00:00.000Z\",\"cwd\":\"/work/moost\"}",
            "{\"type\":\"message\",\"id\":\"m1\",\"parentId\":null,"
                + "\"timestamp\":\"2026-03-01T00:00:01.000Z\",\"message\":{\"role\":\"user\","
                + "\"content\":[{\"type\":\"text\",\"text\":\"最初の質問です\"}]}}",
            "{\"type\":\"message\",\"id\":\"m2\",\"parentId\":\"m1\","
                + "\"timestamp\":\"2026-03-01T00:00:02.000Z\",\"message\":{\"role\":\"assistant\","
                + "\"content\":[{\"type\":\"thinking\",\"thinking\":\"hmm\"},"
                + "{\"type\":\"text\",\"text\":\"了解しました\"}]}}",
        ]
        try lines.joined(separator: "\n").write(
            to: piDir.appendingPathComponent("2026-03-01T00-00-00_\(sessionId).jsonl"),
            atomically: true, encoding: String.Encoding.utf8)

        let model = makeModel()
        let session = RecentSession(
            agentId: "pi", sessionId: sessionId, projectPath: "/work/moost",
            lastPrompt: "最初の質問です", updatedAt: Date(), aiTitle: nil)

        model.openSessionDetail(session)
        XCTAssertEqual(model.screen, .sessionDetail(session))
        model.requestSummary(session)

        await waitUntil { !model.isSummarizing }
        XCTAssertNil(model.summaryError)
        XCTAssertTrue(model.summaryText.contains("最初の質問です"))
        XCTAssertTrue(model.summaryText.contains("了解しました"))
    }

    func test_pi_summary_missing_session_sets_error() async throws {
        let model = makeModel()
        let session = sampleSession(agentId: "pi")

        model.openSessionDetail(session)
        model.requestSummary(session)

        await waitUntil { !model.isSummarizing }
        XCTAssertEqual(model.summaryText, "")
        XCTAssertNotNil(model.summaryError)
    }
}
