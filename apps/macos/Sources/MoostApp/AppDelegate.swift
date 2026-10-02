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
    }

    @MainActor
    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // 表示を先に出して、データはバックグラウンドで更新する
            // （design.md 6.1「手動リロード不要」、同期 I/O で開きを待たせない）
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 設定は変更時に保存済み（design.md 6.6）。終了時の書き戻しは不要。
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
