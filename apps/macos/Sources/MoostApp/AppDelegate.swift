import AppKit
import SwiftUI

/// トレイ常駐本体。Dock アイコンなし（accessory）/ ポップオーバー 570x660 固定。
/// design.md 6 章（NSStatusItem + NSPopover）の native 実装。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    let model = AppModel.defaultApp()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "doc.text.magnifyingglass",
                                   accessibilityDescription: "moost") {
                button.image = image
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = AppInfo.popoverSize
        let host = NSHostingController(rootView: AppRootView().environmentObject(model))
        popover.contentViewController = host
        self.popover = popover

        // 初回起動時は v1 → v2 移行もここで走る（DataMigration）
        model.bootstrap()

        #if DEBUG
        runUISmokeIfRequested()
        #endif
    }

    @MainActor
    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // アプリケーションをアクティブ化してから表示する（1 回目の暗転対策）。
            // ただし NSPopover は再表示時にウィンドウが key にならないことがあり
            // （実機で 2 回目以降の暗転として観測）、show 後に makeKey を
            // 再度行う必要がある（下記の async ブロック）。
            NSApp.activate(ignoringOtherApps: true)
            // 表示を先に出して、データはバックグラウンドで更新する
            // （design.md 6.1「手動リロード不要」、同期 I/O で開きを待たせない）
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.refresh()
            // show 直後はウィンドウがまだキーになっていないことがあるため、
            // 次のランループで確実にキーへ（暗転の解消）。
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.popover?.contentViewController?.view.window
                else { return }
                if !window.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                }
            }
        }
    }

    #if DEBUG
    /// 開発用の UI スモーク（MOOST_UI_SMOKE=1 で有効）。
    /// ポップオーバーの開閉を 2 回繰り返し、各回の実描画を PNG に保存する。
    /// アプリ自身のウィンドウは画面収録権限なしで CGWindowListCreateImage に
    /// 取得できるため、スクリーンショット権限が無い環境でも確認できる。
    private func runUISmokeIfRequested() {
        guard ProcessInfo.processInfo.environment["MOOST_UI_SMOKE"] == "1" else { return }
        print("SMOKE: start")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            // 1 回目
            togglePopover(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            print("SMOKE sessions=\(model.sessions.count) memos=\(model.memos.count) projects=\(model.projects.count)")
            capturePopover(to: "/tmp/moost-popover-1.png")
            // 閉じて 2 回目（ユーザー報告: 2 回目が暗転）
            togglePopover(nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            togglePopover(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            capturePopover(to: "/tmp/moost-popover-2.png")
            // プロジェクトタブ
            model.switchTab(.projects)
            try? await Task.sleep(nanoseconds: 400_000_000)
            capturePopover(to: "/tmp/moost-popover-3.png")
            NSApp.terminate(nil)
        }
    }

    private func capturePopover(to path: String) {
        guard let popover, let window = popover.contentViewController?.view.window else {
            print("SMOKE: no window")
            return
        }
        let windowID = CGWindowID(window.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, windowID,
            [.boundsIgnoreFraming, .bestResolution]) else {
            print("SMOKE: capture failed window=\(window.windowNumber)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("SMOKE: captured \(path) key=\(window.isKeyWindow)")
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        // 設定は変更時に保存済み（design.md 6.6）。終了時の書き戻しは不要。
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
