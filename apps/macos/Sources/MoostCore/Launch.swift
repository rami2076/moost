import Foundation

/// 復帰先ターミナル。settings.json の terminalApp に保存される文字列は
/// Dart 実装と共通なので、値域も同じまま保つ（"Terminal.app" / "iTerm2" / "gnome-terminal"）。
/// リファレンス実装: packages/core/lib/src/terminal_launcher.dart
public enum TerminalApp: String {
    case terminal = "Terminal.app"
    case iterm2 = "iTerm2"
    case gnomeTerminal = "gnome-terminal"

    /// 未知の値（手書き編集・旧バージョン等）は OS の既定へフォールバックする。
    /// macOS native 実装での既定は Terminal.app（Linux 既定の分岐は Dart 側が担う）。
    public static func fromSetting(_ value: String) -> TerminalApp {
        TerminalApp(rawValue: value) ?? .terminal
    }
}

/// ターミナル起動の失敗。UI 側はこれを捕まえてトーストを出す
/// （ポップオーバーにダイアログを出さない — design.md 7 章）。
public struct TerminalLaunchError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
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

    public init(runCommand: (([String]) -> (exit: Int32, stdout: String, stderr: String))? = nil) {
        // デフォルト引数のある execute は関数参照にできないためクロージャで包む。
        self.runCommand = runCommand ?? { TerminalLauncher.execute($0) }
    }

    public func launch(terminal: TerminalApp, command: String) throws {
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
        }
        let result = runCommand(args)
        if result.exit != 0 {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalLaunchError(terminal.rawValue + ": " + reason)
        }
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
    public func launch(settingValue: String, command: String) throws {
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
        // 常に create window すると「復元窓 + 新窓」で 2 窓になってしまう（実機検証済み）。
        // 既存ウィンドウがある場合はそのウィンドウに新規タブを追加し、ウィンドウ数を増やさない。
        let q = scalarQuote
        let nl = scalarNewline
        let escaped = escapeForAppleScript(command)
        return "tell application " + q + "iTerm" + q + nl
            + "  activate" + nl
            + "  if (count of windows) = 0 then" + nl
            + "    set newWindow to (create window with default profile)" + nl
            + "    tell current session of newWindow" + nl
            + "      write text " + q + escaped + q + nl
            + "    end tell" + nl
            + "  else" + nl
            + "    tell current window" + nl
            + "      create tab with default profile" + nl
            + "      tell current session" + nl
            + "        write text " + q + escaped + q + nl
            + "      end tell" + nl
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
