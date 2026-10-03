import XCTest
@testable import MoostCore

/// フェーズ B′ の起動層（spec conformance G1 / G2 と H 項の macOS 側）。
/// リファレンス実装 packages/core/test/terminal_launcher_test.dart と同じ観点を持たせる。
///
/// データ契約の既知項目は SpecConformanceTests が担うので、ここでは
/// 復帰コマンドの組み立てと osascript への受け渡しだけを確かめる。
final class LaunchTests: XCTestCase {

    private let q = TerminalLauncher.scalarQuote
    private let bs = TerminalLauncher.scalarBackslash

    // MARK: 復帰コマンドの組み立て（G2）

    func test_claude_resume_pattern_matches_spec_g2() {
        let command = ResumeCommand.claudeResume(
            projectPath: "/work/alpha", sessionId: "0f0f0f0f-1111")
        XCTAssertTrue(command.hasPrefix("cd '/work/alpha' && "), command)
        XCTAssertTrue(command.contains("claude --resume " + "'0f0f0f0f-1111'"), command)
    }

    func test_claude_resume_unsets_claude_code_env_vars() {
        // Issue #52: cd はシェルの組み込みなので env の対象にしない（cd より後に env）
        let command = ResumeCommand.claudeResume(projectPath: "/w", sessionId: "s")
        guard let envStart = command.range(of: "env -u ")?.lowerBound,
              let cdStart = command.range(of: "cd ")?.lowerBound else {
            XCTFail("env プレフィックスまたは cd が見つからない: " + command); return
        }
        XCTAssertLessThan(cdStart, envStart, "cd && の後に env -u ... で起動する形")
        XCTAssertTrue(command.contains("-u CLAUDE_CODE_SESSION_ID"))
        XCTAssertTrue(command.contains("-u AI_AGENT"))
        XCTAssertTrue(command.contains(" -u AI_AGENT claude --resume "))
    }

    func test_codex_resume_omits_cd_when_project_path_is_empty() {
        // session_meta が読めなかったセッション（spec E6 系。resume はどこからでも効く）
        XCTAssertEqual(
            ResumeCommand.codexResume(projectPath: "", sessionId: "s-1"),
            "codex resume 's-1'")
        XCTAssertEqual(
            ResumeCommand.codexResume(projectPath: "/w", sessionId: "s-1"),
            "cd '/w' && codex resume 's-1'")
    }

    func test_new_session_commands_take_no_session_id() {
        // ADR-004: 新規セッションは sessionId を取らない。Dart の
        // shell_escape_test.dart「builds cd && claude without --resume」と同形
        XCTAssertEqual(
            ResumeCommand.claudeNewSession(projectPath: "/w"),
            "cd '/w' && " + claudeCodeEnvUnsetPrefix() + "claude")
        XCTAssertFalse(ResumeCommand.claudeNewSession(projectPath: "/w").contains("--resume"))
        XCTAssertEqual(ResumeCommand.codexNewSession(projectPath: "/w"), "cd '/w' && codex")
    }

    func test_resume_dispatches_on_agent_id() {
        XCTAssertNotNil(ResumeCommand.resume(agent: "claude-code", projectPath: "/w", sessionId: "s"))
        XCTAssertNotNil(ResumeCommand.resume(agent: "codex", projectPath: "/w", sessionId: "s"))
        XCTAssertNotNil(ResumeCommand.resume(agent: "pi", projectPath: "/w", sessionId: "s"))
        // 対応アダプタを外したメモなど（UI 側はトーストで告知する経路）
        XCTAssertNil(ResumeCommand.resume(agent: "unknown", projectPath: "/w", sessionId: "s"))
        XCTAssertNil(ResumeCommand.newSession(agent: "unknown", projectPath: "/w"))
    }

    // MARK: シェルエスケープ（G1: 注入が作動しない）

    func test_resume_command_neutralises_injected_shell_payloads() {
        let dangerousProject = "/tmp/a b'; touch /tmp/pwned; echo '"
        let dangerousSession = "s\" && rm -rf / \" && echo done"
        let claude = ResumeCommand.claudeResume(
            projectPath: dangerousProject, sessionId: dangerousSession)
        // 期待値は手打ちせず、検証済みの shellEscape（conformance G1 で合格している）から導く。
        // 単一引用符で囲む・中の引用符は「引用符 + バックスラッシュ + 引用符 + 引用符」で返す。
        let escapedProject = shellEscape(dangerousProject)
        let escapedSession = shellEscape(dangerousSession)
        // 期待値は手打ちせず、検証済みの shellEscape（conformance G1 で合格している）から
        // 組み立てた完全一致で検査する。shellEscape 自体は "'" -> "'\\''" の
        // 閉じ・駆け抜け・開きなので、エスケープ列に "'; touch " という部分文字列が
        // 生じてもシェル上は単一引用符内で安全（contains のナイーブ判定は誤検出になる）。
        XCTAssertEqual(
            claude,
            "cd " + escapedProject + " && " + claudeCodeEnvUnsetPrefix()
                + "claude --resume " + escapedSession)
        // 単一引用符そのものは引用符・バックスラッシュ・引用符・引用符で返す
        XCTAssertTrue(escapedProject.contains("\\'"), escapedProject)

        let pipe = ResumeCommand.codexResume(projectPath: "/x`id`", sessionId: "a|b&&c")
        XCTAssertEqual(pipe, "cd " + shellEscape("/x`id`") + " && codex resume " + shellEscape("a|b&&c"))
    }

    // MARK: pi（PiAdapter 相当。Issue #68: provider / model を起動時に渡す）

    func test_pi_resume_cds_and_calls_pi_session() {
        XCTAssertEqual(
            ResumeCommand.piResume(projectPath: "/a b/c", sessionId: "01aaaa-xyz"),
            "cd '/a b/c' && pi --session '01aaaa-xyz'")
    }

    func test_pi_new_session_starts_pi_in_directory() {
        XCTAssertEqual(ResumeCommand.piNewSession(projectPath: "/work/moost"),
                       "cd '/work/moost' && pi")
    }

    func test_pi_resume_passes_provider_and_model() {
        XCTAssertEqual(
            ResumeCommand.piResume(projectPath: "/work/moost", sessionId: "01bbbb",
                                   provider: "dspark", model: "deepseek-v4-flash-0731"),
            "cd '/work/moost' && pi --session '01bbbb' "
                + "--provider 'dspark' --model 'deepseek-v4-flash-0731'")
        XCTAssertEqual(
            ResumeCommand.piNewSession(projectPath: "/work/moost",
                                       provider: "dspark", model: "deepseek-v4-flash-0731"),
            "cd '/work/moost' && pi --provider 'dspark' --model 'deepseek-v4-flash-0731'")
    }

    func test_pi_resume_with_only_model_omits_provider_and_cd() {
        XCTAssertEqual(
            ResumeCommand.piResume(projectPath: "", sessionId: "01cccc", model: "Qwen3-8B-AWQ"),
            "pi --session '01cccc' --model 'Qwen3-8B-AWQ'")
    }

    // MARK: osascript への受け渡し（H: AppleScript エスケープ / 単一 -e）

    /// 実行を差し替えてスクリプト文字列だけを検査する（Dart テストの arrange と同じ型）。
    private func captureLaunch(terminal: TerminalApp, command: String,
                               exit: Int32 = 0, stderr: String = "")
        -> (args: [[String]], error: TerminalLaunchError?) {
        var args: [[String]] = []
        let launcher = TerminalLauncher { received in
            args.append(received)
            return (exit, "", stderr)
        }
        var thrown: TerminalLaunchError?
        do {
            try launcher.launch(terminal: terminal, command: command)
        } catch let error as TerminalLaunchError {
            thrown = error
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
        return (args, thrown)
    }

    func test_terminal_launch_uses_command_file_via_open() throws {
        // Terminal.app は AppleScript ではなく .command ファイル + open（LaunchServices）で開く。
        // 署名なしアプリからの Apple Events は tccd の確認で 9 秒ブロックするため（実機計測）。
        var received: [[String]] = []
        let launcher = TerminalLauncher { args in
            received.append(args)
            return (0, "", "")
        }
        try launcher.launch(terminal: .terminal, command: "cd /tmp && echo hi")
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].first, "/usr/bin/open")
        XCTAssertEqual(received[0][1], "-a")
        XCTAssertEqual(received[0][2], "Terminal")
        guard received[0].count == 4 else {
            XCTFail("open の引数は 4 つ想定: \(received[0])"); return
        }
        let file = received[0][3]
        XCTAssertTrue(file.hasSuffix(".command"), file)
        let content = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertEqual(content, "#!/bin/zsh\ncd /tmp && echo hi\n")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: file))
        try? FileManager.default.removeItem(atPath: file)
    }

    func test_terminal_script_for_iterm2_opens_window_and_writes_text() {
        let (args, _) = captureLaunch(terminal: .iterm2, command: "echo hi")
        let script = args[0][1]
        // iTerm2 の AppleScript 名は "iTerm"（"iTerm2" だと -2741 になる）
        XCTAssertTrue(script.contains("tell application " + q + "iTerm" + q), script)
        // 既存ウィンドウがあれば新規ウィンドウを増やさずタブを追加する（2 窓問題対策）
        XCTAssertTrue(script.contains("count of windows"), script)
        // 復元完了前に count を評価すると 2 窓になるため、ウィンドウが現れるまでポーリングで待つ
        XCTAssertTrue(script.contains("repeat while"), script)
        XCTAssertTrue(script.contains("delay 0.3"), script)
        // Moost が起動させた場合（未実行時）は復元タブを再利用して 1 窓 1 タブを保つ
        XCTAssertTrue(script.contains("wasRunning"), script)
        XCTAssertTrue(script.contains("else if"), script)
        XCTAssertTrue(script.contains("create window with default profile"), script)
        XCTAssertTrue(script.contains("create tab with default profile"), script)
        XCTAssertTrue(script.contains("write text"), script)
    }

    func test_applescript_escapes_quotes_and_backslashes() {
        let (args, _) = captureLaunch(
            terminal: .iterm2,
            command: "cd " + q + "/a b" + q + " && x" + bs + "y")
        let script = args[0][1]
        let escapedQuote = bs + q
        XCTAssertTrue(script.contains(escapedQuote + "/a b" + escapedQuote), script)
        XCTAssertTrue(script.contains("x" + bs + bs + "y"), script)
    }

    func test_gnome_terminal_setting_falls_back_to_terminal_script_on_macos() {
        let (args, _) = captureLaunch(terminal: .gnomeTerminal, command: "echo hi")
        XCTAssertTrue(args[0][1].contains("tell application " + q + "Terminal" + q))
    }

    func test_from_setting_falls_back_for_unknown_value() {
        XCTAssertEqual(TerminalApp.fromSetting("iTerm2"), .iterm2)
        XCTAssertEqual(TerminalApp.fromSetting("Alacritty"), .terminal)
        XCTAssertEqual(TerminalApp.fromSetting(""), .terminal)
    }

    func test_launch_error_carries_stderr_reason() {
        let (_, error) = captureLaunch(terminal: .iterm2, command: "x",
                                      exit: 1, stderr: "boom\n")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.message.contains("boom") ?? false, error?.message ?? "")
        XCTAssertTrue(error?.message.hasPrefix("iTerm2:") ?? false)
    }

    func test_launch_with_setting_value_string() throws {
        var received: [String] = []
        let launcher = TerminalLauncher { args in
            received = args
            return (0, "", "")
        }
        try launcher.launch(settingValue: "iTerm2", command: "echo hi")
        XCTAssertEqual(received.first, "-e")
        XCTAssertTrue(received[1].contains("iTerm"))
    }

    // MARK: 差し替え経路の契約（実行環境に依存しない検査）

    func test_injected_runner_receives_dash_e_and_single_script() throws {
        // iTerm2 経路の既定実装と同じ受け渡しになっていることを、差し替えた実行で確かめる。
        var received: [[String]] = []
        let launcher = TerminalLauncher { args in
            received.append(args)
            return (0, "", "")
        }
        try launcher.launch(terminal: .iterm2, command: "echo hi")
        XCTAssertEqual(received, [["-e", TerminalLauncher.iterm2Script("echo hi")]])
    }

    func test_scripts_keep_the_dart_reference_shape() {
        // Dart の _iterm2Script / _terminalScript と同じ構成（tell / activate / do script）。
        // terminalScript は gnome-terminal フォールバック用に残っている。
        let terminal = TerminalLauncher.terminalScript("x")
        let iterm = TerminalLauncher.iterm2Script("x")
        XCTAssertTrue(terminal.hasPrefix("tell application "))
        XCTAssertTrue(terminal.hasSuffix("end tell"))
        XCTAssertTrue(terminal.contains("do script"))
        XCTAssertTrue(iterm.contains("create window with default profile"))
        XCTAssertTrue(iterm.contains("write text"))
        XCTAssertFalse(terminal.contains("iTerm"))
    }

    // MARK: 既定実装（execute）のタイムアウト

    func test_execute_times_out_and_reports_reason() {
        // osascript の delay 5 を 1 秒で打ち切り、exit 124 + タイムアウト文言を返す。
        let (exit, stdout, stderr) = TerminalLauncher.execute(["-e", "delay 5"], timeout: 1)
        XCTAssertEqual(exit, 124, stderr)
        XCTAssertTrue(stderr.contains("タイムアウト"), stderr)
        _ = stdout
    }

    func test_execute_returns_fast_for_short_script() {
        let (exit, _, stderr) = TerminalLauncher.execute(["-e", "return 0"], timeout: 5)
        XCTAssertEqual(exit, 0, stderr)
    }
}