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
    /// osascript 実行を差し替え可能にする（テスト用）。
    public let runOsascript: ([String]) -> (exit: Int32, stdout: String, stderr: String)

    public init(runOsascript: (([String]) -> (exit: Int32, stdout: String, stderr: String))? = nil) {
        self.runOsascript = runOsascript ?? TerminalLauncher.execute
    }

    public func launch(terminal: TerminalApp, command: String) throws {
        // macOS 上で gnome-terminal が選ばれることはないが、万一に備えて
        // Terminal.app 相当にフォールバックする（Dart 実装と同じ判断）。
        let script: String
        switch terminal {
        case .terminal, .gnomeTerminal:
            script = TerminalLauncher.terminalScript(command)
        case .iterm2:
            script = TerminalLauncher.iterm2Script(command)
        }
        let result = runOsascript(["-e", script])
        if result.exit != 0 {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalLaunchError(terminal.rawValue + ": " + reason)
        }
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

    static func terminalScript(_ command: String) -> String {
        let q = scalarQuote
        let nl = scalarNewline
        let escaped = escapeForAppleScript(command)
        return "tell application " + q + "Terminal" + q + nl
            + "  activate" + nl
            + "  do script " + q + escaped + q + nl
            + "end tell"
    }

    static func iterm2Script(_ command: String) -> String {
        let q = scalarQuote
        let nl = scalarNewline
        let escaped = escapeForAppleScript(command)
        return "tell application " + q + "iTerm2" + q + nl
            + "  activate" + nl
            + "  set newWindow to (create window with default profile)" + nl
            + "  tell current session of newWindow" + nl
            + "    write text " + q + escaped + q + nl
            + "  end tell" + nl
            + "end tell"
    }

    /// 既定の実装。osascript を単発し、stdout / stderr を集める。
    ///
    /// パイプのデッドロック回避（design.md 7 章）: waitUntilExit() より先に
    /// 両ハンドルを読み切る。先に待つと、大容量の出力でパイプが満杯になることがある。
    private static func execute(_ args: [String]) -> (exit: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript", isDirectory: false)
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            let detail = String(describing: error)
            return (-1, "", "osascript を起動できませんでした: " + detail)
        }
        let collectedOut = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let collectedErr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return (process.terminationStatus, collectedOut, collectedErr)
    }
}
