import AppKit
import MoostCore
import SwiftUI

/// トレイ常駐本体。Dock アイコンなし（accessory）/ ポップオーバー 570x660 固定。
/// design.md 6 章（NSStatusItem + NSPopover）の native 実装。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// fileImporter などのシート/パネル完了後にポップオーバー状態を戻すための参照。
    static weak var shared: AppDelegate?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    let model = AppModel.defaultApp()

    /// fileImporter（NSOpenPanel シート）を閉じた後、ポップオーバーの transient 挙動
    /// （外側クリックで閉じる）を復元する。スモーク実測（2026-10-03）: シート表示の前後で
    /// 「別アプリを前面にしたときポップオーバーが閉じるか」を検証したところ、
    /// シートの後は閉じなくなった（NSPopover がシート終了で非アクティブ監視を失う）。
    /// behavior 再設定やキー復元では直らないため、performClose → show で
    /// ポップオーバーの内部監視を作り直す（ユーザー報告 2026-10-03）。
    func restoreTransientPopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async {
            if let window = popover.contentViewController?.view.window, !window.isKeyWindow {
                window.makeKey()
            }
        }
    }

    /// アプリが非アクティブになったらポップオーバーを閉じる（自前 transient）。
    /// NSPopover の .transient は NSOpenPanel の表示（シート/独立ウィンドウとも）後に
    /// 非アクティブ監視を失うことがスモーク実測で判明（2026-10-03）。そのため
    /// .applicationDefined + didResignActive 通知で「moost 以外の場所をクリックで閉じる」
    /// を確実に再現する（ユーザー報告 2026-10-03）。
    private var didResignActiveObserver: NSObjectProtocol?

    @objc private func closePopoverWhenInactive() {
        guard let popover, popover.isShown else { return }
        popover.performClose(nil)
        // didResignActive 後に閉じる。クリックによって resignActive された場合の一瞬の
        // 再表示を防ぐ（メニューバー再クリックで開くのは togglePopover が担当）。
    }

    /// プロジェクト登録用の NSOpenPanel をポップオーバーのシートとして表示する。
    /// SwiftUI の .fileImporter はポップオーバーの transient 挙動を壊すため使わず、
    /// beginSheetModal でポップオーバー自身にシートを付けることで、
    /// 選択/キャンセル後も「外側クリックで閉じる」本来の挙動を保つ。
    @MainActor
    func beginProjectPanel(onSelect: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "登録プロジェクトの選択"
        panel.message = "新規セッションを開始したいディレクトリを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "登録"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = panel.url {
                onSelect(url.path)
            } else {
                onSelect(nil) // キャンセル: 何も変更しない（Flutter 版と同挙動）
            }
            self?.restoreTransientPopover()
        }
        // 2026-10-03 検証: beginSheetModal はポップオーバーの transient（外側クリックで
        // 閉じる）を恒久的に壊すことがスモーク実測で判明。シートを使わず、
        // 独立ウィンドウとして表示する（ポップオーバー自体は閉じない）。
        panel.begin(completionHandler: completion)
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
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
        // .transient は NSOpenPanel 表示後に非アクティブ監視を失う（スモーク実測 2026-10-03）
        // ため、.applicationDefined + didResignActive の自前実装で外側クリック閉じるを再現する。
        popover.behavior = .applicationDefined
        popover.contentSize = AppInfo.popoverSize
        let host = NSHostingController(rootView: AppRootView().environmentObject(model))
        popover.contentViewController = host
        self.popover = popover
        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.closePopoverWhenInactive()
        }

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
            // メモタブ（行ボタン確認用）
            model.switchTab(.memos)
            try? await Task.sleep(nanoseconds: 400_000_000)
            capturePopover(to: "/tmp/moost-popover-4.png")
            // セッション詳細（初期表示の折りたたみ確認用）
            model.switchTab(.sessions)
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let first = model.sessions.first {
                model.openSessionDetail(first)
                try? await Task.sleep(nanoseconds: 500_000_000)
                capturePopover(to: "/tmp/moost-popover-5.png")
                // メモ登録（インラインセッション詳細の確認用）
                model.openNewMemo(for: first)
                try? await Task.sleep(nanoseconds: 400_000_000)
                capturePopover(to: "/tmp/moost-popover-6.png")
                model.backToList(returningTo: .sessions)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            // transient の実測（外側クリック相当 = Finder を前面に = アプリ非アクティブ化）
            model.switchTab(.projects)
            try? await Task.sleep(nanoseconds: 300_000_000)
            deactivateByActivatingFinder()
            try? await Task.sleep(nanoseconds: 800_000_000)
            print("SMOKE transient-before shown=\(popover?.isShown ?? false)") // 期待 false（正常なら閉じる）
            // シートを開く（まず再表示）
            NSApp.activate(ignoringOtherApps: true)
            togglePopover(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.requestRegisterProject()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let keyPanel = NSApp.keyWindow as? NSSavePanel
            print("SMOKE importer sheet=\(keyPanel != nil) behavior=\(popover?.behavior.rawValue ?? -1)")
            capturePopover(to: "/tmp/moost-popover-7.png")
            keyPanel?.cancel(nil)
            try? await Task.sleep(nanoseconds: 500_000_000)
            // 修正検証: restoreTransientPopover 後にポップオーバーが再びキーになるか
            AppDelegate.shared?.restoreTransientPopover()
            try? await Task.sleep(nanoseconds: 300_000_000)
            print("SMOKE after restore keyPopup=\(NSApp.keyWindow === popover?.contentViewController?.view.window)")
            deactivateByActivatingFinder()
            try? await Task.sleep(nanoseconds: 800_000_000)
            print("SMOKE transient-after shown=\(popover?.isShown ?? false)") // 期待 false（シート後も閉じる）
            // Terminal 起動テスト（MOOST_UI_SMOKE_LAUNCH=1。TCC 権限の実測用）
            if ProcessInfo.processInfo.environment["MOOST_UI_SMOKE_LAUNCH"] == "1" {
                runLaunchSmoke()
            }
            NSApp.terminate(nil)
        }
    }

    /// ターミナル起動経路（openInTerminal と同一）をアプリプロセスから実測する。
    /// 署名なし SPM バイナリから Apple Events（osascript）が通るか確認するための
    /// 切り分け用。成功/失敗は stdout に "LAUNCHSMOKE:" で出力する。
    /// 外側クリック相当の transient 実測: Finder を前面に出す（アプリ非アクティブ化）。
    /// CGEventPost はアクセシビリティ権限が要るため、別アプリの activate で代用する。
    private func deactivateByActivatingFinder() {
        if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            finder.activate(options: [])
            print("SMOKE: finder activated")
        } else {
            print("SMOKE: finder not found")
        }
    }

    private func runLaunchSmoke() {
        let sessionId = ProcessInfo.processInfo.environment["MOOST_TEST_SESSION"] ?? ""
        // スモークはセッション一覧の読み込み（非同期）に依存しないよう、
        // 見つからない場合は固定コマンドで起動経路だけを確認する。
        let command: String
        if let session = model.sessions.first(where: { $0.sessionId == sessionId }),
           let c = ResumeCommand.resume(
               agent: session.agentId,
               projectPath: session.projectPath,
               sessionId: session.sessionId,
               provider: model.settings.piProvider,
               model: model.settings.piModel) {
            command = c
        } else {
            print("LAUNCHSMOKE: session not found (\(sessionId)), using fallback command")
            command = "echo moost-smoke"
        }
        let start = Date()
        do {
            try TerminalLauncher().launch(settingValue: model.settings.terminalApp, command: command)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            print("LAUNCHSMOKE: OK \(elapsed)s \(command)")
        } catch {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            print("LAUNCHSMOKE: FAILED \(elapsed)s \(error)")
        }
        // Terminal.app（.command + open）経路の実測。Apple Events を使わないため
        // 0.2 秒程度で返り、数秒後に Terminal が新規ウィンドウで実行するはず。
        let marker = "/tmp/moost-terminal-command-ran"
        try? FileManager.default.removeItem(atPath: marker)
        let t0 = Date()
        do {
            try TerminalLauncher().launch(terminal: .terminal, command: "touch " + marker)
            let dt = String(format: "%.2f", Date().timeIntervalSince(t0))
            print("LAUNCHSMOKE TERMINAL_APP=OK \(dt)s marker=\(marker)")
        } catch {
            let dt = String(format: "%.2f", Date().timeIntervalSince(t0))
            print("LAUNCHSMOKE TERMINAL_APP=FAILED \(dt)s \(error)")
        }
        // ウィンドウ数の確認（iTerm2 が 2 窓になる問題の切り分け用）:
        // 起動後に何枚ウィンドウが増えたかを AppleScript で検査する。
        let winCount = TerminalLauncher.execute(["-e", "tell application \"iTerm\"\n  count windows\nend tell"])
        print("LAUNCHSMOKE ITERM_WINDOWS=\(winCount.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) exit=\(winCount.exit)")
    }

    private func capturePopover(to path: String) {
        guard let popover, let window = popover.contentViewController?.view.window else {
            print("SMOKE: no window")
            return
        }
        // 主経路: 実画面キャプチャ（ウィンドウサーバー経由。暗転もそのまま写る）。
        // 再表示直後はウィンドウが CGWindowList に登録されるまで少し時間がかかる
        // ことがあるため数回リトライする。
        let windowID = CGWindowID(window.windowNumber)
        for attempt in 0..<3 {
            if let cgImage = CGWindowListCreateImage(
                .null, .optionIncludingWindow, windowID,
                [.boundsIgnoreFraming, .bestResolution]) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                    print("SMOKE: captured \(path) key=\(window.isKeyWindow)")
                    return
                }
            } else if attempt == 2 {
                // macOS 26 ではウィンドウサーバー経由のキャプチャが失敗することが
                // ある（画面収録権限まわりの制限）。その場合はアプリ自身のビュー
                // 階層を直接レンダリングして PNG を作る（サーバー不要で確実）。
                // 暗転（ウィンドウサーバー側の減光）は写らないため、回帰検出は
                // 後続の key=\(window.isKeyWindow) ログ側で担保する。
                renderViewFallback(view: window.contentView, label: window.isKeyWindow, to: path)
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        print("SMOKE: capture failed window=\(window.windowNumber)")
    }

    /// NSView を直接ビットマップへ描画するフォールバック（CGWindowList 不使用）。
    /// key はウィンドウサーバーを経由しないため暗転は写らないが、キー状態は
    /// ウィンドウオブジェクトから取得できるので回帰検出はログ側で行う。
    private func renderViewFallback(view: NSView?, label key: Bool, to path: String) {
        guard let view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("SMOKE: render fallback failed")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("SMOKE: captured \(path) key=\(key)")
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        // 設定は変更時に保存済み（design.md 6.6）。終了時の書き戻しは不要。
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
