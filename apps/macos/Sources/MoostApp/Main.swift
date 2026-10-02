import AppKit
import Foundation

// moost のエントリ。
// - 引数なし / GUI 起動: トレイ常駐アプリ（NSStatusItem + NSPopover、Dock アイコンなし）
// - `moost mcp`: アプリ内蔵 MCP サーバー（stdio JSON-RPC。第 3 インクリメント）
// - `moost --version`: バージョン表示
@main
struct MoostMain {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--version") {
            print(AppInfo.version)
            return
        }
        if arguments.first == "mcp" {
            MCPServerCLI.run()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement=true 相当（Info.plist を持たない SPM 実行ファイルのため）。
        // applicationShouldTerminateAfterLastWindowClosed も false を返す。
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
