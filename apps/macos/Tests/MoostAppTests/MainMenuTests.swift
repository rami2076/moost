import AppKit
import XCTest
@testable import MoostApp

/// mainMenu（MainMenuBuilder）の構造テスト。
/// native 版でコピー&ペーストが効かない原因が「編集メニュー未設置」であるため、
/// キー等価と action の組み合わせが崩れたら即座に落とす（回帰ゲート）。
final class MainMenuTests: XCTestCase {
    private var menu: NSMenu!

    override func setUp() {
        super.setUp()
        menu = MainMenuBuilder.build()
    }

    override func tearDown() {
        menu = nil
        super.tearDown()
    }

    private func editItem(_ title: String) -> NSMenuItem? {
        MainMenuBuilder.editMenu(in: menu)?.item(withTitle: title)
    }

    func testEditMenuExists() {
        let editMenu = MainMenuBuilder.editMenu(in: menu)
        XCTAssertNotNil(editMenu, "編集メニューが存在すること（これが無いと Cmd+C/V が効かない）")
    }

    func testCutCopyPasteSelectAll() {
        let cut = editItem("カット")
        XCTAssertEqual(cut?.action, #selector(NSText.cut(_:)))
        XCTAssertEqual(cut?.keyEquivalent, "x")
        XCTAssertEqual(cut?.keyEquivalentModifierMask, [.command])

        let copy = editItem("コピー")
        XCTAssertEqual(copy?.action, #selector(NSText.copy(_:)))
        XCTAssertEqual(copy?.keyEquivalent, "c")
        XCTAssertEqual(copy?.keyEquivalentModifierMask, [.command])

        let paste = editItem("ペースト")
        XCTAssertEqual(paste?.action, #selector(NSText.paste(_:)))
        XCTAssertEqual(paste?.keyEquivalent, "v")
        XCTAssertEqual(paste?.keyEquivalentModifierMask, [.command])

        let selectAll = editItem("すべてを選択")
        XCTAssertEqual(selectAll?.action, #selector(NSText.selectAll(_:)))
        XCTAssertEqual(selectAll?.keyEquivalent, "a")
        XCTAssertEqual(selectAll?.keyEquivalentModifierMask, [.command])
    }

    func testUndoRedo() {
        let undo = editItem("取り消し")
        XCTAssertEqual(undo?.action, Selector(("undo:")))
        XCTAssertEqual(undo?.keyEquivalent, "z")

        let redo = editItem("やり直し")
        XCTAssertEqual(redo?.action, Selector(("redo:")))
        XCTAssertEqual(redo?.keyEquivalent, "z")
        XCTAssertEqual(redo?.keyEquivalentModifierMask, [.command, .shift])
    }

    func testQuitKeyEquivalent() {
        let quit = menu.items
            .compactMap { $0.submenu?.items }
            .flatMap { $0 }
            .first(where: { $0.action == #selector(NSApplication.terminate(_:)) })
        XCTAssertNotNil(quit, "Cmd+Q で終了できること（アプリメニュー）")
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(quit?.keyEquivalentModifierMask, [.command])
    }
}
