import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // トレイ常駐アプリなので、ウィンドウを隠して（閉じて）も終了しない。
    // 終了はフッターの「終了」またはトレイメニューからのみ行う
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
