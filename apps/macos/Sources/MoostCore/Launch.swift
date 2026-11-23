import CoreGraphics
import Foundation

/// 復帰先ターミナル。settings.json の terminalApp に保存される文字列は
/// Dart 実装と共通なので、値域も同じまま保つ
/// （"Terminal.app" / "iTerm2" / "gnome-terminal" / "kitty" / "zed" / "herdr"）。
/// "kitty" と "zed" と "herdr" は Dart 側が未知値として Terminal.app へフォールバックするため、
/// Flutter 版で選ばれていても壊れない（native のみの拡張値）。
/// リファレンス実装: packages/core/lib/src/terminal_launcher.dart
public enum TerminalApp: String {
    case terminal = "Terminal.app"
    case iterm2 = "iTerm2"
    case gnomeTerminal = "gnome-terminal"
    case kitty = "kitty"
    /// Zed（zed.dev）。エディタ同梱の統合ターミナルへ復帰コマンドを流す
    /// 外部 CLI を持たないため、ワークスペースを開いてコマンドをクリップボードへ
    /// 預ける導線になる（Issue #131。制約は zedLaunch 参照）。
    case zed = "zed"
    /// Herdr（herdr.dev）。herdr-core（`hc`）がターミナルを実行し、
    /// デスクトップアプリ herdr-app が表示する構成（Issue #130）。
    case herdr = "herdr"

    /// 未知の値（手書き編集・旧バージョン等）は OS の既定へフォールバックする。
    /// macOS native 実装での既定は Terminal.app（Linux 既定の分岐は Dart 側が担う）。
    public static func fromSetting(_ value: String) -> TerminalApp {
        TerminalApp(rawValue: value) ?? .terminal
    }
}

/// ターミナル起動の失敗。UI 側はこれを捕まえてトーストを出す
/// （ポップオーバーにダイアログを出さない — design.md 7 章）。
/// LocalizedError: トーストは error.localizedDescription を使うため、
/// これを実装しないと汎用文言（The operation couldn't be completed.）になる。
public struct TerminalLaunchError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// ターミナル起動の結果種別。Kitty は「既存ウィンドウにタブ」で開けるかが
/// kitty.conf の設定に依存するため、UI 側で開き方をトーストへ反映する。
public enum TerminalLaunchOutcome: Equatable, Sendable {
    /// 既存ウィンドウのタブとして開いた（Kitty の kitten @ launch --type=tab）。
    case tab
    /// 新しいウィンドウ（または新規インスタンス）として開いた。
    case window
    /// Zed の復帰: ワークスペースウィンドウを開き、復帰コマンドを
    /// クリップボードへコピーした（コマンド自体はユーザーが貼って実行する）。
    /// Zed には外部から統合ターミナルへコマンドを流す CLI / AppleScript /
    /// ソケット API が無いため、これが現状の最大自動化工線（Issue #131、
    /// zedLaunch の方式選定を参照）。
    case clipboard
    /// Herdr の復帰: herdr-app が現在のスペースの新規タブとして開いた
    /// （focus:false なので前面タブは切り替わらず背面で開く）。
    /// 作成された herdr ターミナル ID を添える（UI がトーストへ出す）。
    case background(terminal: String)
}

/// claude 由来の環境変数（Issue #52）。Moost 自身のプロセスがこれを持ったまま
/// ターミナルへ引き継がれると、ここで起動する claude が子セッションと誤認識されうる。
/// リファレンス実装 knownClaudeCodeEnvVarNames（claude_code_environment.dart）と同内容。
public let knownClaudeCodeEnvVarNames: [String] = [
    "CLAUDECODE",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_ENABLE_TELEMETRY",
    "CLAUDE_EFFORT",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
    "CLAUDE_CODE_EXECPATH",
    "CLAUDE_PID",
    "AI_AGENT",
]

/// "env -u VAR1 -u VAR2 ... " 形のシェルコマンドプレフィックス。
/// 未設定の変数でも env はエラーにならないため、汚染の有無を問わず常に付けてよい。
public func claudeCodeEnvUnsetPrefix() -> String {
    "env " + knownClaudeCodeEnvVarNames.map { "-u " + $0 }.joined(separator: " ") + " "
}

/// 復帰・新規セッションのコマンドを組み立てる（spec conformance G1 / G2）。
/// リファレンス実装: claude_code_adapter.dart / codex_adapter.dart の
/// buildResumeCommand / buildNewSessionCommand。
public enum ResumeCommand {
    /// アダプタ識別子。リファレンス実装の agentId（'claude-code' / 'codex' / 'pi'）と一致させる。
    public static let claudeAgentId = "claude-code"
    public static let codexAgentId = "codex"
    public static let piAgentId = "pi"
    public static let hermesAgentId = "hermes"

    /// claude 用。claude の直前だけ env -u で環境変数を外す（Issue #52）。
    /// cd はシェルの組み込みコマンドなので env の対象にしない。
    public static func claudeResume(projectPath: String, sessionId: String) -> String {
        "cd " + shellEscape(projectPath) + " && "
            + claudeCodeEnvUnsetPrefix() + "claude --resume " + shellEscape(sessionId)
    }

    public static func claudeNewSession(projectPath: String) -> String {
        "cd " + shellEscape(projectPath) + " && "
            + claudeCodeEnvUnsetPrefix() + "claude"
    }

    /// codex 用。session_meta が読めなかったセッションは projectPath が空になりうる。
    /// resume 自体はどこからでも効くので cd を付けない。
    public static func codexResume(projectPath: String, sessionId: String) -> String {
        let resume = "codex resume " + shellEscape(sessionId)
        if projectPath.isEmpty {
            return resume
        }
        return "cd " + shellEscape(projectPath) + " && " + resume
    }

    public static func codexNewSession(projectPath: String) -> String {
        "cd " + shellEscape(projectPath) + " && codex"
    }

    /// pi 用。リファレンス実装 PiAdapter._build と同じく、settings の
    /// piProvider / piModel が指定されていれば --provider / --model を付ける（Issue #68）。
    public static func piResume(projectPath: String, sessionId: String,
                                provider: String = "", model: String = "") -> String {
        piCommand(prefix: "pi --session " + shellEscape(sessionId),
                  projectPath: projectPath, provider: provider, model: model)
    }

    public static func piNewSession(projectPath: String,
                                    provider: String = "", model: String = "") -> String {
        piCommand(prefix: "pi", projectPath: projectPath, provider: provider, model: model)
    }

    private static func piCommand(prefix: String, projectPath: String,
                                  provider: String, model: String) -> String {
        var flags: [String] = []
        if !provider.isEmpty { flags.append("--provider " + shellEscape(provider)) }
        if !model.isEmpty { flags.append("--model " + shellEscape(model)) }
        var command = prefix
        if !flags.isEmpty { command += " " + flags.joined(separator: " ") }
        if projectPath.isEmpty { return command }
        return "cd " + shellEscape(projectPath) + " && " + command
    }

    /// hermes 用。`hermes chat --resume <id>` は記録済み cwd へ自動復帰する
    /// （`--no-restore-cwd` で無効化可能。hermes-agent v0.22.3 実機確認）が、
    /// codex と同様に projectPath があれば cd しておく（無害・表示上も一貫）。
    /// 新規セッションは `hermes chat` をそのまま起動する。
    public static func hermesResume(projectPath: String, sessionId: String) -> String {
        let resume = "hermes chat --resume " + shellEscape(sessionId)
        if projectPath.isEmpty { return resume }
        return "cd " + shellEscape(projectPath) + " && " + resume
    }

    public static func hermesNewSession(projectPath: String) -> String {
        "cd " + shellEscape(projectPath) + " && hermes chat"
    }

    /// herdr 復帰で tab.new の argv に渡すシェル起動形（Issue #130）。
    /// herdr-app は argv をプログラムとして直接起動するため、復帰コマンド
    /// 文字列はシェルに預ける（実機検証 2026-11-19: 復帰後の `hc read` で
    /// cd / 復帰コマンドの実行を確認済み）。kitty 経路の /bin/zsh -lc と同じ形。
    public static func herdrShellArgv(command: String) -> [String] {
        ["/bin/zsh", "-lc", command]
    }

    /// アダプタ識別子（Memo.agent / RecentSession.agentId）から復帰コマンドを組み立てる。
    /// 未知のエージェントは nil を返す（UI 側は「不明な agent」のトーストを出す）。
    public static func resume(agent: String, projectPath: String, sessionId: String,
                              provider: String = "", model: String = "") -> String? {
        switch agent {
        case claudeAgentId:
            return claudeResume(projectPath: projectPath, sessionId: sessionId)
        case codexAgentId:
            return codexResume(projectPath: projectPath, sessionId: sessionId)
        case piAgentId:
            return piResume(projectPath: projectPath, sessionId: sessionId,
                            provider: provider, model: model)
        case hermesAgentId:
            return hermesResume(projectPath: projectPath, sessionId: sessionId)
        default:
            return nil
        }
    }

    /// アダプタ識別子から新規セッションのコマンドを組み立てる（ADR-004）。
    public static func newSession(agent: String, projectPath: String,
                                  provider: String = "", model: String = "") -> String? {
        switch agent {
        case claudeAgentId:
            return claudeNewSession(projectPath: projectPath)
        case codexAgentId:
            return codexNewSession(projectPath: projectPath)
        case piAgentId:
            return piNewSession(projectPath: projectPath, provider: provider, model: model)
        case hermesAgentId:
            return hermesNewSession(projectPath: projectPath)
        default:
            return nil
        }
    }
}

/// ターミナルを開いて復帰コマンドを実行する。
/// リファレンス実装: terminal_launcher.dart の _launchMacos 系。
/// osascript への受け渡しは「-e + スクリプト 1 本」の単一経路に絞る。
public final class TerminalLauncher {
    /// コマンド実行を差し替え可能にする（テスト用）。
    /// osascript（iTerm2）と /usr/bin/open（Terminal.app）の両方を受け止める。
    public let runCommand: ([String]) -> (exit: Int32, stdout: String, stderr: String)
    private let kittenPathProvider: () -> String?
    private let socketCandidatesProvider: () -> [String]
    private let zedBinaryProvider: () -> String?
    /// クリップボードへの書き込み（テストから差し替え可能。既定は NSPasteboard）。
    private let clipboardWriter: (String) -> Void
    /// cd が読めないコマンドの Zed 起動先フォールバック（既定はFileManager の cwd）。
    private let zedFallbackDirectoryProvider: () -> String
    private let herdrBinaryProvider: () -> String?
    /// herdr 復帰時に tab.new / terminal.open へ渡す作業ディレクトリ。
    /// テストから差し替え可能（実ファイルシステムに依存しない検証用）。
    private let herdrWorkingDirectoryProvider: () -> String

    /// herdr-app が起動してから復帰タブが開けるまでの待ち上限。
    /// open -a Herdr はバックグラウンド復帰なので、実測 1 秒前後で
    /// herdr-app.sock ができる（余白を持って 8 秒）。
    /// テストから差し替え可能（init の herdrWindowLaunchTimeout 引数）。
    public let herdrWindowLaunchTimeout: TimeInterval

    /// open -a からの再試行間隔（秒）。既定 0.25 秒（ソケット生成は通常 1 秒以内）。
    public static let herdrRetryInterval: TimeInterval = 0.25
    /// 再試行ループの待機（テストから仮想時間へ差し替え可能）。
    private let retrySleep: (TimeInterval) -> Void
    /// 再試行ループの現在時刻（テストから仮想時間へ差し替え可能）。
    private let retryNow: () -> TimeInterval

    public init(
        runCommand: (([String]) -> (exit: Int32, stdout: String, stderr: String))? = nil,
        kittenPathProvider: (() -> String?)? = nil,
        socketCandidatesProvider: (() -> [String])? = nil,
        zedBinaryProvider: (() -> String?)? = nil,
        clipboardWriter: ((String) -> Void)? = nil,
        zedFallbackDirectoryProvider: (() -> String)? = nil,
        herdrBinaryProvider: (() -> String?)? = nil,
        herdrWorkingDirectoryProvider: (() -> String)? = nil,
        herdrWindowLaunchTimeout: TimeInterval? = nil,
        herdrRetrySleep: ((TimeInterval) -> Void)? = nil,
        herdrRetryNow: (() -> TimeInterval)? = nil
    ) {
        // デフォルト引数のある execute は関数参照にできないためクロージャで包む。
        self.runCommand = runCommand ?? { TerminalLauncher.execute($0) }
        self.kittenPathProvider = kittenPathProvider ?? { TerminalLauncher.findKittyBinary() }
        self.socketCandidatesProvider = socketCandidatesProvider ?? {
            TerminalLauncher.kittySocketCandidates()
        }
        self.zedBinaryProvider = zedBinaryProvider ?? { TerminalLauncher.findZedBinary() }
        // 既定のクリップボード書き込みは AppKit 側（MoostApp）から注入する。
        // MoostCore は AppKit に依存しないため、注入が無いときは書き込まない
        // （ワークスペース起動は成功し、トーストでコマンド全文を案内する）。
        self.clipboardWriter = clipboardWriter ?? { _ in }
        self.zedFallbackDirectoryProvider = zedFallbackDirectoryProvider
            ?? { FileManager.default.currentDirectoryPath }
        self.herdrBinaryProvider = herdrBinaryProvider ?? { TerminalLauncher.findHerdrAppBinary() }
        // herdr 復帰は復帰コマンドの cd から folder を取るため、cwd プロバイダは
        // 通常使われない（cd が読めないコマンドだけのフォールバック経路）。
        // 既定は FileManager の cwd（cwd 取得の意図に合わせる）。ProcessInfo の
        // PWD は親から継いだ古い値になりうるため主経路にしない。
        self.herdrWorkingDirectoryProvider = herdrWorkingDirectoryProvider
            ?? { FileManager.default.currentDirectoryPath }
        self.herdrWindowLaunchTimeout = herdrWindowLaunchTimeout ?? 8
        self.retrySleep = herdrRetrySleep ?? { interval in
            usleep(useconds_t(interval * 1_000_000))
        }
        self.retryNow = herdrRetryNow ?? { Date().timeIntervalSince1970 }
    }

    @discardableResult
    public func launch(terminal: TerminalApp, command: String) throws -> TerminalLaunchOutcome {
        // macOS 上で gnome-terminal が選ばれることはないが、万一に備えて
        // Terminal.app 相当にフォールバックする（Dart 実装と同じ判断）。
        let args: [String]
        switch terminal {
        case .terminal:
            // Terminal.app は AppleScript (do script) ではなく .command ファイル + open で開く。
            // 署名なしアプリからの Apple Events は tccd への確認が 9 秒かかり、
            // メインスレッドをブロックする要因になる（2026-10-02 実機計測済み）。
            // open は LaunchServices 経由で 0.2 秒程度（シェルからの実測 0.15s）。
            let file = try TerminalLauncher.writeCommandFile(command: command)
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(atPath: file)
            }
            args = ["/usr/bin/open", "-a", "Terminal", file]
        case .iterm2:
            args = ["-e", TerminalLauncher.iterm2Script(command)]
        case .gnomeTerminal:
            args = ["-e", TerminalLauncher.terminalScript(command)]
        case .kitty:
            return try kittyLaunch(command: command)
        case .zed:
            return try zedLaunch(command: command)
        case .herdr:
            return try herdrLaunch(command: command)
        }
        let result = runCommand(args)
        if result.exit != 0 {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalLaunchError(terminal.rawValue + ": " + reason)
        }
        return .window
    }

    // MARK: Kitty（AppleScript 非対応のためリモコン経由で開く）

    /// Kitty のリモコン用ソケットの基底パス。kitty.conf には下記の 2 行を案内する:
    ///   allow_remote_control yes
    ///   listen_on unix:/tmp/moost-kitty.sock
    /// ただし kitty は設定ファイル由来の listen_on に PID を付与する
    /// （unix:/tmp/moost-kitty.sock → /tmp/moost-kitty.sock-<pid>。
    /// CLI の --listen-on では付与されない — kitty main.py expand_listen_on）。
    /// そのため Moost は固定パスだけでなく、前面ウィンドウのオーナー PID から
    /// 推測した候補を順に試す（kittySocketCandidates）。
    public static let kittyControlSocket = "unix:/tmp/moost-kitty.sock"

    /// 実際のリモコンソケット候補（試行順: 前面ウィンドウのインスタンス → CLI 固定パス
    /// → 残りのウィンドウインスタンス → グロブ）。
    /// windowPids / globbed / socketExists はテストから差し替え可能。
    /// - windowPids: 画面上の kitty ウィンドウのオーナー PID（手前から）
    /// - globbed: /tmp の moost-kitty.sock-*（CGWindowList に載らないもの用）
    /// - socketExists: ソケットファイルの実在判定（既定はファイルシステム）
    public static func kittySocketCandidates(
        windowPids: [Int32] = kittyWindowOwnerPids(),
        globbed: [String] = kittyGlobbedSocketPaths(),
        socketExists: (String) -> Bool = { socket in TerminalLauncher.kittySocketFileExists(socket) }
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func add(_ socket: String) {
            guard socketExists(socket), !seen.contains(socket) else { return }
            seen.insert(socket)
            result.append(socket)
        }
        // 1) 最前面ウィンドウのインスタンス（config の listen_on は -<pid> が付く）
        if let front = windowPids.first {
            add(kittyControlSocket + "-" + String(front))
        }
        // 2) CLI の --listen-on で固定パスを listen しているインスタンス
        add(kittyControlSocket)
        // 3) 残りのウィンドウインスタンス（手前から）
        for pid in windowPids.dropFirst() {
            add(kittyControlSocket + "-" + String(pid))
        }
        // 4) 最小化などで CGWindowList に出ないインスタンスをグロブで回収
        for path in globbed { add(path) }
        return result
    }

    /// 画面上の kitty ウィンドウのオーナー PID を手前から返す（重複除去）。
    /// kitty のウィンドウはマスターインスタンス（listen_on の PID 付与元）が所有する
    /// （2026-10-21 実機検証: ウィンドウオーナー PID == ソケットの -<pid>）。
    /// kCGWindowName は画面収録権限が要るが、OwnerName / OwnerPID は不要。
    public static func kittyWindowOwnerPids() -> [Int32] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var pids: [Int32] = []
        for window in windows {
            guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "kitty",
                  let pid = window[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if !pids.contains(pid) { pids.append(pid) }
        }
        return pids
    }

    /// /tmp 上の moost-kitty.sock-* を "unix:" 付きで列挙する。
    public static func kittyGlobbedSocketPaths() -> [String] {
        let base = String(kittyControlSocket.dropFirst("unix:".count))
        let dir = (base as NSString).deletingLastPathComponent
        let prefix = (base as NSString).lastPathComponent + "-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { "unix:" + dir + "/" + $0 }
    }

    /// "unix:/path" のプレフィックスを外してソケットファイルの実在を調べる。
    public static func kittySocketFileExists(_ socket: String) -> Bool {
        let path = socket.hasPrefix("unix:") ? String(socket.dropFirst("unix:".count)) : socket
        return FileManager.default.fileExists(atPath: path)
    }

    /// kitten/kitty CLI の探索先（リモコン経路で使用）。
    public static let kittyBinaryCandidates: [String] = [
        "/Applications/kitty.app/Contents/MacOS/kitten",
        "/Applications/kitty.app/Contents/MacOS/kitty",
        "/opt/homebrew/bin/kitten",
        "/opt/homebrew/bin/kitty",
        "/usr/local/bin/kitten",
        "/usr/local/bin/kitty",
    ]

    /// 実行可能な kitten（または kitty）を探す。戻り値はリモコン経路の `kitten @` に使う。
    /// Homebrew とアプリバンドル内を順に確認し、見つからなければ PATH を探索する
    /// （GUI アプリから起動した場合は PATH が狭いため、通常は上の固定候補で見つかる）。
    public static func findKittyBinary() -> String? {
        let fm = FileManager.default
        for path in kittyBinaryCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathVar.split(separator: ":").map(String.init) where !dir.isEmpty {
            for name in ["kitten", "kitty"] {
                let candidate = dir + "/" + name
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// Kitty で復帰コマンドを開く。AppleScript 非対応のため 2 段構え:
    /// 1) リモコン（kitten @ --to <socket> launch --type=tab）で前面ウィンドウの
    ///    インスタンスに新規タブ。kitty.conf の allow_remote_control yes と
    ///    listen_on unix:/tmp/moost-kitty.sock が設定され、かつ Kitty がその設定で
    ///    起動済みである場合のみ成功する（listen_on はリロード非対応）。
    ///    ソケットは設定ファイル由来だと PID が付与されるため、ウィンドウの
    ///    オーナー PID から候補を作り、手前から順に試す（kittySocketCandidates）。
    /// 2) 不可なら /usr/bin/open -n -a kitty --args ... で新規インスタンスの
    ///    ウィンドウとして開く（設定不要・AppleScript 不要・非ブロッキング）。
    /// write text ではなく起動引数でコマンドを渡すため、
    /// 復帰コマンドは /bin/zsh -lc 経由でそのまま実行される。
    private func kittyLaunch(command: String) throws -> TerminalLaunchOutcome {
        let shell = ["/bin/zsh", "-lc", command]
        // 1) タブ経路。kitten バイナリが見つからない場合は新規ウィンドウへ直行する。
        // 注意: コマンド引数の区切りに "--" を使うと Go 版 CLI では実行されなかった
        // （2026-10-21 実機確認）。オプション解析は先頭が非オプションの時点で終わるため
        // ここでは "--" を挟まない。
        if let kitten = kittenPathProvider() {
            for socket in socketCandidatesProvider() {
                // ソケットが生きているか（古いソケットはすぐ失敗して次の候補へ）
                let alive = runCommand([kitten, "@", "--to", socket, "ls"])
                guard alive.exit == 0 else { continue }
                let result = runCommand([kitten, "@", "--to", socket,
                                         "launch", "--type=tab"] + shell)
                if result.exit == 0 { return .tab }
                // 応答はあるが launch が失敗した場合も次の候補を試す
            }
        }
        // 2) 新規ウィンドウ経路（既存インスタンスへは入らなくても起動は成功する）
        let opened = runCommand(["/usr/bin/open", "-n", "-a", "kitty", "--args"] + shell)
        if opened.exit == 0 {
            return .window
        }
        let reason = opened.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = reason.isEmpty ? "" : "（" + reason + "）"
        throw TerminalLaunchError("Kitty: 起動できませんでした" + detail)
    }

    // MARK: Zed（ワークスペース起動 + クリップボード案内）

    /// Zed CLI（`cli` バイナリ）の探索先。Zed.app には CLI が同梱されているが
    /// PATH へはインストールされない（`cli: install cli binary` を実行した
    /// ユーザーのみ /usr/local/bin/zed に置く）。GUI アプリから起動した場合は
    /// PATH が狭いため、固定候補を優先する（kitty と同じ方針）。
    public static let zedBinaryCandidates: [String] = [
        "/Applications/Zed.app/Contents/MacOS/cli",
        "/usr/local/bin/zed",
        "/opt/homebrew/bin/zed",
    ]

    /// 実行可能な Zed CLI を探す。固定候補 → PATH の順。
    public static func findZedBinary() -> String? {
        let fm = FileManager.default
        for path in zedBinaryCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathVar.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = dir + "/zed"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Zed が見つからない場合のトースト文言（kitty / herdr と同じ扱い）。
    public static let zedNotFoundMessage =
        "Zed: Zed.app が見つかりません。Zed をインストールするか、"
        + "復帰先を Terminal.app / iTerm2 / Kitty に切り替えてください。"

    /// Zed で復帰コマンドを開く（Issue #131）。
    ///
    /// 方式選定（実機検証 2026-11-19、Zed 1.28.1 / Zed-aarch64.dmg、
    /// /Applications/Zed.app、~/.config/zed 実在を確認）:
    /// Zed はエディタ同梱の統合ターミナルを持つが、外部からターミナルへ
    /// コマンドを流す口を何も公開していない:
    /// - CLI（`zed <path>`）はファイル/ディレクトリ/`zed://` URL を開くのみ。
    ///   `zed --terminal -e <cmd>` 系は未実装（zed-industries/zed
    ///   Discussion #57026 で機能依頼がオープンな状態）。実機でも `cli <dir>` は
    ///   ワークスペースを開くだけでコマンド実行の口は無い。
    /// - `zed://` スキームは settings / extension / git/clone 等を開けるだけで
    ///   ターミナル起動の kind を持たない（crates/zed/src/main.rs の
    ///   OpenRequestKind に terminal 系は無く、未知の kind は no-op）。
    /// - AppleScript 辞書なし（sdef 無し）。OSascript 自動化権限も要る。
    /// - cli バイナリとアプリ間の IPC は対外 API でない（CliRequest は
    ///   Open / SetOpenBehavior / DebugState の 3 種でターミナル起動は無い）。
    /// - ターミナルへのキー注入（候補 c）は Accessibility 権限が必須で、
    ///   Zed 側のキーマップ変更で静かに壊れる（実機でも CGEvent 注入が
    ///   通らないことを確認）。本番の復帰導線にしない。
    /// - Zed の task システム（tasks.json / task::Spawn アクション）は
    ///   ワークスペースを開いた Zed の UI / keymap からのみ起動でき、
    ///   復帰コマンドごとに動的なターミナル起動はできない。
    /// したがって Issue 方針の (a) を採用する:
    /// 1) Zed CLI で projectPath をワークスペースとして開く
    ///    （既存ウィンドウがあれば前面化のみ）。
    /// 2) 復帰コマンドをクリップボードへコピーし、UI がトーストで
    ///    「Zed のターミナル（⌃`）でペーストして実行」と案内する。
    /// コマンド実行はユーザーの 1 ポストに委ねる（自動実行ではない）ことを
    /// CHANGELOG と設定画面の注意に明記する。
    ///
    /// projectPath は ResumeCommand が必ず先頭に付ける `cd '<path>' && ...`
    /// から取り出す（cd が読めないコマンド — codex の projectPath 空
    /// セッション等 — は zedFallbackDirectoryProvider へ倒す）。
    private func zedLaunch(command: String) throws -> TerminalLaunchOutcome {
        guard let zed = zedBinaryProvider() else {
            throw TerminalLaunchError(TerminalLauncher.zedNotFoundMessage)
        }
        let directory = Self.zedWorkspaceDirectory(for: command,
                                                   fallback: zedFallbackDirectoryProvider())
        // -n（新規ワークスペース）にしない: 復帰先はプロジェクトの既存ウィンドウを
        // 前面化するのが動線上自然（open_behavior の既定挙動に任せる）。
        let args: [String]
        if directory.isEmpty {
            args = [zed]
        } else {
            args = [zed, directory]
        }
        let opened = runCommand(args)
        if opened.exit != 0 {
            let reason = opened.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = reason.isEmpty ? "" : "（" + reason + "）"
            throw TerminalLaunchError("Zed: ワークスペースを開けませんでした" + detail)
        }
        // ワークスペースが開けたらコマンドをクリップボードへ預ける。
        // 書き込みは呼び出し側（MoostApp の NSPasteboard 実装）に委譲する。
        clipboardWriter(command)
        return .clipboard
    }

    /// 復帰コマンド文字列の先頭 `cd '<projectPath>' && ...` から起動ディレクトリを
    /// 取り出す。ResumeCommand 系の形式に依存する。引用符の走査は POSIX シェルの
    /// 引用規則に従う:
    /// - 引用符内で '\''（閉じ + バックスラッシュ + 引用符 + 開き）が続く場合は
    ///   shellEscape が ' をエスケープした列なので 4 文字を 1 単位としてコピーし
    ///   引用符状態を変えない（単純 toggle だと o'\''x で状態が反転して誤抽出に
    ///   なる。Support.swift の shellEscape の逆変換も同時に適用するため、
    ///   ここはトークンを正確に切り出すことが目的）。
    /// - 引用符内の ''（リテラル引用符）は 2 文字で 1 文字としてコピーし、
    ///   閉じ引用符と区別する。
    /// - 引用符外で ' && ' が現れたらトークン終わり。
    /// cd が読めない場合はフォールバックへ倒す。
    static func zedWorkspaceDirectory(for command: String, fallback: String) -> String {
        let cdPrefix = "cd "
        guard command.hasPrefix(cdPrefix) else { return fallback }
        let rest = command.dropFirst(cdPrefix.count)
        var token = ""
        var inQuote = false
        var index = rest.startIndex
        while index < rest.endIndex {
            let ch = rest[index]
            if inQuote, ch == "'",
               rest.index(after: index) < rest.endIndex {
                let nextCh = rest[rest.index(after: index)]
                if nextCh == "\\" {
                    // shellEscape が ' を '\''（閉じ引用符 + バックスラッシュ +
                    // 引用符 + 開き引用符）に展開した列: 4 文字を 1 単位として
                    // コピーし引用符状態を変えない（単純 toggle だと
                    // o'\''x で状態が反転して誤抽出になる）。
                    let end = rest.index(index, offsetBy: 3)
                    token.append(contentsOf: rest[index...end])
                    if end == rest.endIndex { break }
                    index = rest.index(after: end)
                    continue
                }
                if nextCh == "'" {
                    // 引用符内のリテラル引用符（''）: 2 文字で 1 文字。
                    token.append(contentsOf: rest[index...rest.index(after: index)])
                    index = rest.index(after: rest.index(after: index))
                    continue
                }
                // 引用符の閉じ。
                inQuote = false
                token.append(ch)
            } else if !inQuote, ch == "'",
                      rest.index(after: index) < rest.endIndex,
                      rest[rest.index(after: index)] == "'" {
                // 引用符外の一時的な引用（''）: 状態を変えずに 2 文字コピー。
                token.append(contentsOf: rest[index...rest.index(after: index)])
                index = rest.index(after: rest.index(after: index))
                continue
            } else if ch == "'" {
                // 開き引用符で状態に入る。
                inQuote = true
                token.append(ch)
            } else if !inQuote, rest[index...].hasPrefix(" && ") {
                break
            } else {
                token.append(ch)
            }
            index = rest.index(after: index)
        }
        if inQuote || token.isEmpty { return fallback }
        // shellEscape の単一引用符を戻す（Support.swift の shellEscape の逆変換）。
        guard token.hasPrefix("'"), token.hasSuffix("'"), token.count >= 2 else {
            return token
        }
        let body = token.dropFirst().dropLast()
        return body.replacingOccurrences(of: "'\\''", with: "'")
    }

    /// Herdr で復帰コマンドを開く（Issue #130）。
    ///
    /// 方式選定（実機検証 2026-11-19、herdr-app 0.1.16 / hc 0.1.21）:
    /// herdr は「herdr-core（hc）がターミナルを実行し、デスクトップアプリ
    /// herdr-app が表示する」構成。復帰動線は **herdr-app の `do tab.new`**:
    /// - `herdr-app do tab.new '{"folder":"<cwd>","argv":["/bin/zsh","-lc",<command>],"focus":false,"name":"moost:resume"}'`
    ///   が 0.015 秒で `{"space":..,"tab":..,"terminal":"t.."}` を返し、
    ///   現在のスペースの新規タブとして復帰ターミナルが開く。
    ///   `focus:false` は前面タブを切り替えない（実機検証: 復帰前後で
    ///   `herdr-app status` の tab / focused_pane が不変）。folder は spawn 前
    ///   検証で、不正 folder は exit 1 + JSON error で確実に取り出せる
    ///   （herdrFolder が復帰コマンドの cd から抽出）。argv はシェル経由で
    ///   直接起動されるため復帰コマンドの注入はシェルエスケープ
    ///   （conformance G1）で担保済み。復帰コマンド自体は cd を含んでいても
    ///   いなくても動く（folder が cwd を決める）。
    /// - 却下案 1: `herdr-app do terminal.open` はフォカスターミナルのペインを
    ///   split するため、復帰のたびにユーザーの画面構成を壊す。
    /// - 却下案 2: `hc run --bg` はラベル無しターミナルが「hidden」になり
    ///   （herdr-app ls に現れない。skill の "Unlabeled workers stay hidden" と
    ///   実機一致）、herdr-app を落とした環境では復帰が見えなくなる。
    ///   ターミナル生成 + hc send の 2 手構成も同じ理由で不可。
    /// - herdr-app は接続先ウィンドウのソケット（~/.config/herdr-app/
    ///   herdr-app.sock）へ接続できる場合のみ成功する。Herdr.app 未起動
    ///   （= ソケット無し）は exit 2 で失敗するため、その場合は open で
    ///   Herdr.app を起動してからソケットが現れるまで再試行する
    ///   （フォールバック）。それでも失敗した場合は TerminalLaunchError を
    ///   投げ、UI 側が「Herdr の開き方」をトーストへ出す（kitty の window
    ///   フォールバックと同様の扱い）。
    private func herdrLaunch(command: String) throws -> TerminalLaunchOutcome {
        guard let app = herdrBinaryProvider() else {
            throw TerminalLaunchError(Self.herdrNotRunningMessage)
        }
        let argv = ResumeCommand.herdrShellArgv(command: command)
        let folder = Self.herdrFolder(for: command, fallback: herdrWorkingDirectoryProvider())
        let payload = Self.herdrTabNewPayload(folder: folder, argv: argv,
                                              name: Self.herdrResumeTabName)
        let first = runCommand([app, "do", "tab.new", payload])
        if case let .success(terminal) = Self.herdrDoResult(first) {
            return .background(terminal: terminal)
        }
        // 1 回目失敗 = Herdr.app 未起動（ソケット待ち）が主因。open で
        // ウィンドウを起動し、ソケットが現れるまで do を再試行する。
        // 原因が terminal.run の spawn 失敗（folder 不正など）の場合は
        // ウィンドウの起動と無関係なので、open せず即失敗にする。
        // 区別に do の exit code を使う（実機検証 2026-11-19）:
        //   未起動（ソケット接続エラー）: exit 2 + プレインテキスト
        //   spawn 失敗:                   exit 1 + JSON error
        // 成功は exit 0 + 作成物 JSON なので、ここに来る exit は 1 / 2 のどちらか。
        let retryAfterOpen = first.exit != 1
        let opened: (exit: Int32, stdout: String, stderr: String) =
            retryAfterOpen ? runCommand(["/usr/bin/open", "-a", "Herdr"]) : (-1, "", "")
        // 失敗理由は最後のリトライ結果を基準にする（最低でも初回結果なので空にはならない）。
        var lastFailure = first
        // 同一応答の連続で打ち切り: spawn 失敗は `{}` exit 0 のように open と
        // 無関係な失敗もあり、そのままでは deadline まで約 32 回叩く
        // （herdrWindowLaunchTimeout 8 秒 / 0.25 秒間隔）。3 回連続で同じ
        // (exit, stdout, stderr) ならソケット待ちの進歩無しとみなして早期に
        // 打ち切る（実機の未起動復帰は 1 秒以内に成功するため 3 回は余裕がある）。
        var previousResponse: (exit: Int32, stdout: String, stderr: String)?
        var identicalStreak = 0
        if opened.exit == 0 {
            // 仮想時間差し替え可能（retryNow / retrySleep）。本番は実時刻 + usleep。
            let deadline = retryNow() + herdrWindowLaunchTimeout
            while retryNow() < deadline {
                retrySleep(Self.herdrRetryInterval) // 0.25 秒間隔（ソケット生成は通常 1 秒以内）
                let retry = runCommand([app, "do", "tab.new", payload])
                if case let .success(terminal) = Self.herdrDoResult(retry) {
                    return .background(terminal: terminal)
                }
                lastFailure = retry
                if let previous = previousResponse, retry == previous {
                    identicalStreak += 1
                    if identicalStreak >= 2 { break } // 同一応答 3 回連続で打ち切り
                } else {
                    previousResponse = retry
                    identicalStreak = 0
                }
            }
        }
        // 最後の試行の理由をそのまま出す（未起動なら open の失敗理由も添える）。
        var reason = Self.herdrFailureReason(stdout: lastFailure.stdout, stderr: lastFailure.stderr)
        if opened.exit != 0 {
            let openReason = opened.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !openReason.isEmpty {
                reason = reason.isEmpty ? openReason : reason + " / " + openReason
            }
        }
        throw TerminalLaunchError("Herdr: 復帰ターミナルを作成できませんでした"
            + (reason.isEmpty ? "" : "（" + reason + "）"))
    }

    /// herdr 復帰の作業ディレクトリ（tab.new の folder）。復帰コマンド文字列は
    /// ResumeCommand が常に先頭へ `cd '<projectPath>' && ...` を付けるため、
    /// そのパスを抽出して folder に使う（実機検証 2026-11-19: tab.new の
    /// folder は spawn 前検証で、不正 folder は exit 1 + JSON error になる。
    /// argv 内の cd が成功しても folder が不正だとターミナル自体が作られない）。
    /// cd が読めないコマンド（codex の projectPath 空セッション等）は
    /// 呼び出し側が渡したフォールバックへ倒す。
    static func herdrFolder(for command: String, fallback: String) -> String {
        let cdPrefix = "cd "
        guard command.hasPrefix(cdPrefix) else { return fallback }
        let rest = command.dropFirst(cdPrefix.count)
        // 引用符の中は区切りとして扱わない（パスに " && " を含むケース）。
        // shellEscape は常に単一引用符で囲むので、閉じ引用符までがトークン。
        var token = ""
        var inQuote = false
        var index = rest.startIndex
        while index < rest.endIndex {
            let ch = rest[index]
            if ch == "'" {
                inQuote.toggle()
                token.append(ch)
            } else if !inQuote, rest[index...].hasPrefix(" && ") {
                break
            } else {
                token.append(ch)
            }
            index = rest.index(after: index)
        }
        if inQuote || token.isEmpty { return fallback }
        return unquote(token)
    }

    /// shellEscape（Support.swift）で作った単一引用符トークンを元に戻す。
    /// 引用符で囲まれていないトークンはそのまま返す。
    /// 中身の '\\'' 復元は shellEscape の逆変換（閉じ・駆け抜け・開きの 3 文字を
    /// ' へ戻す）に一致する（Issue #130 の実装時に確認済み）。
    static func unquote(_ token: String) -> String {
        guard token.count >= 2, token.hasPrefix("'"), token.hasSuffix("'") else {
            return token
        }
        let body = token.dropFirst().dropLast()
        // shellEscape は ' を '\''（閉じ・駆け抜け・開き）でエスケープするため、
        // 逆変換は '\'' → ' の置換で復元できる。
        return body.replacingOccurrences(of: "'\\''", with: "'")
    }

    /// tab.new に渡す JSON を組み立てる。
    /// argv / name は JSON 値なので JSONSerialization で作る（エスケープ事故を
    /// 防ぐ。Support.swift の MoostJSON と同じ趣旨）。name はタブ名に反映され、
    /// プログラム終了後も残る（実機検証 2026-11-19: tab.new --name は即座に
    /// herdr-app ls のタブ名へ反映、復帰後のシェルに残っても不変。
    /// tab.rename は不要）。
    static func herdrTabNewPayload(folder: String, argv: [String], name: String) -> String {
        var payload: [String: Any] = ["focus": false, "argv": argv, "name": name]
        if !folder.isEmpty { payload["folder"] = folder }
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            // JSONSerialization が失敗する入力はありえないが、その場は
            // folder なしの最小構成に倒す（復帰コマンドの実行は続ける）。
            return "{\"focus\":false,\"argv\":[\"/bin/zsh\",\"-lc\",\"echo moost\"]}"
        }
        return json
    }

    /// 復帰タブの名前。herdr-app のタブ名になり、復帰タブを後から探せる
    /// （skill の "Pick an explicit, useful name" に従う）。
    public static let herdrResumeTabName = "moost:resume"

    /// `herdr-app do` の結果。tab.new は作成物の JSON
    /// （`{"space":..,"tab":..,"terminal":"t.."}`）を返し、失敗時は exit!=0 か
    /// `{"error": ...}` を返す（実機検証済み）。
    /// 判定の要点（実機検証 2026-11-19）:
    /// - tab.new は spawn 失敗でも `{}`（空オブジェクト、exit 0）で返すことが
    ///   ある。terminal キーの有無が生死の分け目なので、これがない場合は
    ///   理由が空でも失敗扱いにする（herdrLaunch が open 再試行へ進み、
    ///   結果的にトーストで失敗を知らせる）。
    /// - 成功時はターミナル ID を返す（UI がトーストで「タブ t..」と示せる）。
    enum HerdrDoResult: Equatable {
        case success(terminal: String)
        case failure(reason: String)
    }

    static func herdrDoResult(_ result: (exit: Int32, stdout: String, stderr: String))
        -> HerdrDoResult {
        func fail() -> HerdrDoResult {
            .failure(reason: Self.herdrFailureReason(stdout: result.stdout,
                                                     stderr: result.stderr))
        }
        guard result.exit == 0 else { return fail() }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // 成功応答は必ず JSON オブジェクト。空・非 JSON・{"error":...} は失敗。
        guard let data = stdout.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["error"] == nil,
              let terminal = json["terminal"] as? String,
              !terminal.isEmpty
        else {
            return fail()
        }
        return .success(terminal: terminal)
    }

    /// herdr 未起動（Herdr.app が見つからない）時のトースト文言。
    /// UI 側のトーストでも同じ文言を使い、設定画面の「注意」にも記載する。
    public static let herdrNotRunningMessage =
        "Herdr: Herdr.app が見つかりません。Herdr をインストールするか、"
        + "復帰先を Terminal.app / iTerm2 / Kitty に切り替えてください。"

    /// hc / herdr-app の失敗理由を JSON から読み出す。JSON でない出力
    /// （usage 文字列や素のテキスト）はそのまま 1 行に圧縮して返す。
    static func herdrFailureReason(stdout: String, stderr: String) -> String {
        for raw in [stdout, stderr] {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["error"] as? String {
                return message
            }
        }
        for raw in [stderr, stdout] {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text.components(separatedBy: .newlines).first ?? text
            }
        }
        return ""
    }

    /// herdr-app（デスクトップアプリ CLI）の実行ファイル探索（Issue #130）。
    /// 実機検証（2026-11-19）: インストーラは /Applications/Herdr.app を置き、
    /// ~/.local/bin/herdr-app はそのバイナリへのシンボリックリンク。
    /// herdr-core はターミナルのホストで、herdr-app の起動に随伴して起動する
    /// （フォールバックの /usr/bin/open -a Herdr が担う）。
    /// GUI アプリから起動した場合は PATH が狭いため、固定候補を優先する。
    public static let herdrAppCandidates: [String] = [
        "/Applications/Herdr.app/Contents/MacOS/Herdr",
        NSString(string: "~/.local/bin/herdr-app").expandingTildeInPath,
    ]

    /// 実行可能な herdr-app を探す。固定候補 → PATH の順。
    public static func findHerdrAppBinary() -> String? {
        let fm = FileManager.default
        for path in herdrAppCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathVar.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = dir + "/herdr-app"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// .command 実行ファイルを一時ディレクトリに書き出す（Terminal.app 用）。
    /// Terminal.app は LaunchServices 経由で .command を新しいウィンドウで実行する
    /// （iTerm2 は .command を実行しないため iTerm2 では使えない）。
    public static func writeCommandFile(command: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("moost-" + UUID().uuidString + ".command")
        // 先頭にシェルを明示する（実行ビット付きでも拡張子 .command でシェルに渡されるため
        // 実質は任意だが、エディタや diff で中身が分かりやすいように付ける）。
        let content = "#!/bin/zsh\n" + command + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// settings.json の terminalApp 値（文字列）から起動する。
    @discardableResult
    public func launch(settingValue: String, command: String) throws -> TerminalLaunchOutcome {
        try launch(terminal: TerminalApp.fromSetting(settingValue), command: command)
    }

    // MARK: AppleScript スクリプト生成
    //
    // 引用符とバックスラッシュはリテラルに書かず Unicode.Scalar から組み立てる
    // （Support.swift の MoostJSON と同じ作製。生テキストのエスケープ事故を防ぐ）。

    static let scalarQuote = String(Unicode.Scalar(0x22)!)
    static let scalarBackslash = String(Unicode.Scalar(0x5c)!)
    static let scalarNewline = String(Unicode.Scalar(0x0a)!)

    /// AppleScript の文字列リテラル用にエスケープする（引用符とバックスラッシュ）。
    /// リファレンス実装 _escape と同じ置換（" は \" へ、\ は \\ へ）。
    static func escapeForAppleScript(_ value: String) -> String {
        var out = ""
        for ch in value.unicodeScalars {
            if ch == Unicode.Scalar(0x5c)! {
                out.unicodeScalars.append(contentsOf: [Unicode.Scalar(0x5c)!, Unicode.Scalar(0x5c)!])
            } else if ch == Unicode.Scalar(0x22)! {
                out.unicodeScalars.append(contentsOf: [Unicode.Scalar(0x5c)!, Unicode.Scalar(0x22)!])
            } else {
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    public static func terminalScript(_ command: String) -> String {
        let q = scalarQuote
        let nl = scalarNewline
        let escaped = escapeForAppleScript(command)
        return "tell application " + q + "Terminal" + q + nl
            + "  activate" + nl
            + "  do script " + q + escaped + q + nl
            + "end tell"
    }

    public static func iterm2Script(_ command: String) -> String {
        // iTerm2 の AppleScript アプリケーション名は "iTerm"（表示名は iTerm2）。
        // "iTerm2" で tell すると -2741 (syntax error) になる（実機検証済み）。
        // iTerm2 は強制終了（kill）後でも次回起動時に前回のウィンドウを復元するため、
        // 常に create window すると「復元窓 + 新窓」で 2 窓になる。
        // さらに復元はアプリ起動直後に完了するが、復元完了前に (count of windows) を
        // 評価すると 0 になり無駄な新規ウィンドウを作る。そのため:
        // 1) ウィンドウが現れるまでポーリング（最大 4.5 秒）
        // 2) ユーザーが既に iTerm2 を使っている（wasRunning）場合は現在の
        //    ウィンドウにタブ追加（作業を壊さない）
        // 3) 今回 Moost が起動させ、復元窓がある場合は、復元タブ（新規シェル）を
        //    再利用して 1 窓 1 タブを保つ（close は MoostApp 発信で 1 窓あたり
        //    約 9 秒かかり 20 秒タイムアウトになるため不採用）
        // 4) ウィンドウが無い場合のみ新規ウィンドウ
        let q = scalarQuote
        let nl = scalarNewline
        let escaped = escapeForAppleScript(command)
        return "tell application " + q + "iTerm" + q + nl
            + "  set wasRunning to application " + q + "iTerm" + q + " is running" + nl
            + "  activate" + nl
            + "  set attemptCount to 0" + nl
            + "  repeat while (count of windows) = 0 and attemptCount < 15" + nl
            + "    delay 0.3" + nl
            + "    set attemptCount to attemptCount + 1" + nl
            + "  end repeat" + nl
            + "  if wasRunning and (count of windows) > 0 then" + nl
            + "    tell current window" + nl
            + "      create tab with default profile" + nl
            + "      tell current session" + nl
            + "        write text " + q + escaped + q + nl
            + "      end tell" + nl
            + "    end tell" + nl
            + "  else if (count of windows) > 0 then" + nl
            + "    tell current window" + nl
            + "      tell current session" + nl
            + "        write text " + q + escaped + q + nl
            + "      end tell" + nl
            + "    end tell" + nl
            + "  else" + nl
            + "    set newWindow to (create window with default profile)" + nl
            + "    tell current session of newWindow" + nl
            + "      write text " + q + escaped + q + nl
            + "    end tell" + nl
            + "  end if" + nl
            + "end tell"
    }

    /// 既定の実装。コマンドを単発し、stdout / stderr を集める。
    ///
    /// 先頭要素が絶対パス（"/" 始まり）ならそれを実行ファイルとして起動し、
    /// それ以外は /usr/bin/osascript として扱う（iTerm2 の AppleScript 経路と
    /// Terminal.app の /usr/bin/open 経路を 1 つの実行フックにまとめるため）。
    ///
    /// パイプのデッドロック回避（design.md 7 章）: waitUntilExit() より先に
    /// 両ハンドルを読み切る。先に待つと、大容量の出力でパイプが満杯になることがある。
    /// タイムアウト（デフォルト 20 秒）付き。Apple Events が返らない場合に
    /// ハングしないよう terminate() で打ち切る。
    public static func execute(_ args: [String], timeout: TimeInterval = 20) -> (exit: Int32, stdout: String, stderr: String) {
        let process = Process()
        let executable: String
        let processArgs: [String]
        if let first = args.first, first.hasPrefix("/") {
            executable = first
            processArgs = Array(args.dropFirst())
        } else {
            executable = "/usr/bin/osascript"
            processArgs = args
        }
        process.executableURL = URL(fileURLWithPath: executable, isDirectory: false)
        process.arguments = processArgs
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            let detail = String(describing: error)
            return (-1, "", "\(executable) を起動できませんでした: " + detail)
        }
        // 出力はバックグラウンドで読み、終了待ちはタイムアウト付きセマフォで行う。
        // 読み込みを先にブロッキングするとタイムアウト監視が始まらないため、
        // readabilityHandler で常時回収する（パイプ満杯も起きない）。
        let outData = ThreadSafeOutput()
        let errData = ThreadSafeOutput()
        out.fileHandleForReading.readabilityHandler = { handle in
            outData.append(handle.availableData)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            errData.append(handle.availableData)
        }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning { process.terminate() }
        }
        timer.resume()
        semaphore.wait()
        timer.cancel()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        let stdout = String(data: outData.data, encoding: .utf8) ?? ""
        let stderr = String(data: errData.data, encoding: .utf8) ?? ""
        if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGTERM {
            return (124, stdout, "osascript が \(timeout) 秒以内に終了しませんでした（タイムアウト）")
        }
        return (process.terminationStatus, stdout, stderr)
    }
}

/// readabilityHandler（@Sendable）から追記されるスレッドセーフな出力バッファ。
private final class ThreadSafeOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
