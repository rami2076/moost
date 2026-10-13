import AppKit

/// メニューバー常駐（LSUIElement）アプリの mainMenu 構築。
///
/// NSApplication に mainMenu を設定しないと、Cmd+C / Cmd+V / Cmd+X / Cmd+A 等の
/// Edit 系ショートカットは AppKit のメニューキー等価経路で解決されず、
/// ポップオーバー内の TextField / TextEditor でコピー&ペーストが効かない
/// （ユーザー報告 2026-10-05: native 版で copy/paste 不可）。
/// アクセサリアプリでも mainMenu を保持していればキー等価は評価されるため、
/// 「編集」メニュー（take nil → レスポンダチェーン）を持つことが唯一の正攻法。
enum MainMenuBuilder {
    /// アプリメニュー名に使う表示名（bundled では CFBundleName、SPM 実行ではプロセス名）。
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    /// mainMenu（アプリメニュー + 編集メニュー）を構築する。
    /// 各メニューアイテムの action は nil target で、レスポンダチェーン
    /// （NSHostingView → フィールドエディタの NSTextView）に委譲する。
    static func build() -> NSMenu {
        let mainMenu = NSMenu()

        // --- アプリメニュー（Cmd+Q で終了できるようにする） ---
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "\(appName) について",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "\(appName) を隠す",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "ほかを隠す",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "すべてを表示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "\(appName) を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        // --- 編集メニュー（コピー&ペーストの本命） ---
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "編集")
        editMenuItem.submenu = editMenu

        editMenu.addItem(
            withTitle: "取り消し",
            action: Selector(("undo:")),
            keyEquivalent: "z")
        let redo = editMenu.addItem(
            withTitle: "やり直し",
            action: Selector(("redo:")),
            keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "カット",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "コピー",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "ペースト",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v")
        let pasteAndMatch = editMenu.addItem(
            withTitle: "ペーストしてスタイルを合わせる",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v")
        pasteAndMatch.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(
            withTitle: "削除",
            action: #selector(NSTextView.delete(_:)),
            keyEquivalent: "\u{8}")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "すべてを選択",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")

        return mainMenu
    }
}

/// テスト用: メインメニューから「編集」サブメニューを返す。
extension MainMenuBuilder {
    static func editMenu(in menu: NSMenu) -> NSMenu? {
        menu.items.first(where: { $0.submenu?.title == "編集" })?.submenu
    }
}
