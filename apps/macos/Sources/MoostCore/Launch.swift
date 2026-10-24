import CoreGraphics
import Foundation

/// 復帰先ターミナル。settings.json の terminalApp に保存される文字列は
/// Dart 実装と共通なので、値域も同じまま保つ
/// （"Terminal.app" / "iTerm2" / "gnome-terminal" / "kitty"）。
/// "kitty" は Dart 側が未知値として Terminal.app へフォールバックするため、
/// Flutter 版で選ばれていても壊れない（native のみの拡張値）。
/// リファレンス実装: packages/core/lib/src/terminal_launcher.dart
public enum TerminalApp: String {
    case terminal = "Terminal.app"
    case iterm2 = "iTerm2"
    case gnomeTerminal = "gnome-terminal"
    case kitty = "kitty"

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

    public init(
        runCommand: (([String]) -> (exit: Int32, stdout: String, stderr: String))? = nil,
        kittenPathProvider: (() -> String?)? = nil,
        socketCandidatesProvider: (() -> [String])? = nil
    ) {
        // デフォルト引数のある execute は関数参照にできないためクロージャで包む。
        self.runCommand = runCommand ?? { TerminalLauncher.execute($0) }
        self.kittenPathProvider = kittenPathProvider ?? { TerminalLauncher.findKittyBinary() }
        self.socketCandidatesProvider = socketCandidatesProvider ?? {
            TerminalLauncher.kittySocketCandidates()
        }
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
