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
        XCTAssertNotNil(ResumeCommand.resume(agent: "hermes", projectPath: "/w", sessionId: "s"))
        // 対応アダプタを外したメモなど（UI 側はトーストで告知する経路）
        XCTAssertNil(ResumeCommand.resume(agent: "unknown", projectPath: "/w", sessionId: "s"))
        XCTAssertNil(ResumeCommand.newSession(agent: "unknown", projectPath: "/w"))
    }

    // MARK: hermes（`hermes chat --resume` / `hermes chat`）

    func test_hermes_resume_cds_and_calls_chat_resume() {
        // cwd は hermes 側が自動復帰するが、codex と同じく cd も付ける（無害・一貫）
        XCTAssertEqual(
            ResumeCommand.hermesResume(projectPath: "/w", sessionId: "local-abc"),
            "cd '/w' && hermes chat --resume 'local-abc'")
        XCTAssertEqual(
            ResumeCommand.hermesResume(projectPath: "", sessionId: "local-abc"),
            "hermes chat --resume 'local-abc'")
    }

    func test_hermes_new_session_starts_chat_in_directory() {
        XCTAssertEqual(ResumeCommand.hermesNewSession(projectPath: "/work/moost"),
                       "cd '/work/moost' && hermes chat")
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
        XCTAssertEqual(TerminalApp.fromSetting("kitty"), .kitty)
        XCTAssertEqual(TerminalApp.fromSetting("herdr"), .herdr)
        XCTAssertEqual(TerminalApp.fromSetting("Alacritty"), .terminal)
        XCTAssertEqual(TerminalApp.fromSetting(""), .terminal)
    }

    func test_launch_error_carries_stderr_reason() {
        let (_, error) = captureLaunch(terminal: .iterm2, command: "x",
                                      exit: 1, stderr: "boom\n")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.message.contains("boom") ?? false, error?.message ?? "")
        XCTAssertTrue(error?.message.hasPrefix("iTerm2:") ?? false)
        // LocalizedError 経由でトースト（error.localizedDescription）にも message が出る
        XCTAssertTrue(error?.localizedDescription.contains("boom") ?? false,
                      error?.localizedDescription ?? "")
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

    // MARK: Kitty（リモコン経由 → 新規ウィンドウへフォールバック）

    func test_kitty_opens_tab_when_remote_control_available() throws {
        // kitty.conf に allow_remote_control yes + listen_on が設定され、Kitty がその
        // 設定で起動済みの場合: プローブ（ls）→ launch --type=tab が成功し、
        // 既存ウィンドウにタブを開く。
        let socket = TerminalLauncher.kittyControlSocket
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                return (0, "", "")
            },
            kittenPathProvider: { "/fake/kitten" },
            socketCandidatesProvider: { [socket] })
        let outcome = try launcher.launch(terminal: .kitty, command: "cd /tmp && echo hi")
        XCTAssertEqual(outcome, .tab)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0], ["/fake/kitten", "@", "--to", socket, "ls"])
        XCTAssertEqual(received[1], [
            "/fake/kitten", "@", "--to", socket,
            "launch", "--type=tab", "/bin/zsh", "-lc", "cd /tmp && echo hi",
        ])
    }

    func test_kitty_uses_pid_suffixed_socket_for_config_listen_on() throws {
        // kitty.conf 由来の listen_on は PID 付与される（/tmp/moost-kitty.sock-<pid>）。
        // 前面ウィンドウのオーナー PID から構築した候補でタブを開く。
        let socket = TerminalLauncher.kittyControlSocket + "-4242"
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                return (0, "", "")
            },
            kittenPathProvider: { "/fake/kitten" },
            socketCandidatesProvider: { [socket] })
        let outcome = try launcher.launch(terminal: .kitty, command: "echo hi")
        XCTAssertEqual(outcome, .tab)
        XCTAssertEqual(received[1], ["/fake/kitten", "@", "--to", socket,
                                     "launch", "--type=tab", "/bin/zsh", "-lc", "echo hi"])
    }

    func test_kitty_tries_next_candidate_when_front_socket_is_stale() throws {
        // 前面のソケットが古い（接続不能）場合、次の候補へ進み、開いたインスタンスへ
        // タブを開く。
        let dead = TerminalLauncher.kittyControlSocket + "-1111"
        let live = TerminalLauncher.kittyControlSocket + "-2222"
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                if args.contains(dead) { return (2, "", "connection refused") }
                return (0, "", "")
            },
            kittenPathProvider: { "/fake/kitten" },
            socketCandidatesProvider: { [dead, live] })
        let outcome = try launcher.launch(terminal: .kitty, command: "echo hi")
        XCTAssertEqual(outcome, .tab)
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received[0], ["/fake/kitten", "@", "--to", dead, "ls"])
        XCTAssertEqual(received[1], ["/fake/kitten", "@", "--to", live, "ls"])
        XCTAssertEqual(received[2], ["/fake/kitten", "@", "--to", live,
                                     "launch", "--type=tab", "/bin/zsh", "-lc", "echo hi"])
    }

    func test_kitty_socket_candidates_orders_front_window_first_and_dedupes() {
        // 純粋関数の並び順: 最前面（存在する場合）→ CLI 固定パス → 残り → グロブ。
        let base = TerminalLauncher.kittyControlSocket
        let front = base + "-11"
        let back = base + "-22"
        let globbed = "unix:/tmp/moost-kitty.sock-33"
        let alive: Set<String> = [front, base, back, globbed]
        let candidates = TerminalLauncher.kittySocketCandidates(
            windowPids: [11, 22],
            globbed: [globbed],
            socketExists: { alive.contains($0) })
        XCTAssertEqual(candidates, [front, base, back, globbed])
    }

    func test_kitty_socket_candidates_prefers_exact_when_front_has_no_pid_socket() {
        // 最前面が CLI の --listen-on 起動（固定パス、PID なし）の場合:
        // 前面 PID ソケットが無ければ固定パスが最初に来る。
        let base = TerminalLauncher.kittyControlSocket
        let back = base + "-22"
        let alive: Set<String> = [base, back]
        let candidates = TerminalLauncher.kittySocketCandidates(
            windowPids: [11, 22],
            globbed: [],
            socketExists: { alive.contains($0) })
        XCTAssertEqual(candidates, [base, back])
    }

    func test_kitty_falls_back_to_new_window_when_remote_control_unavailable() throws {
        // allow_remote_control 未設定（既定 no）や Kitty 未起動ではタブ経路が失敗するため、
        // 設定不要の /usr/bin/open -n -a kitty --args で新規ウィンドウを開く。
        let socket = TerminalLauncher.kittyControlSocket
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                if args.contains("ls") || args.contains("launch") {
                    return (2, "", "Failed to connect to unix:/tmp/moost-kitty.sock")
                }
                return (0, "", "")
            },
            kittenPathProvider: { "/fake/kitten" },
            socketCandidatesProvider: { [socket] })
        let outcome = try launcher.launch(terminal: .kitty, command: "echo hi")
        XCTAssertEqual(outcome, .window)
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0], ["/fake/kitten", "@", "--to", socket, "ls"])
        XCTAssertEqual(received[1], ["/usr/bin/open", "-n", "-a", "kitty",
                                     "--args", "/bin/zsh", "-lc", "echo hi"])
    }

    func test_kitty_skips_tab_when_kitten_binary_missing() throws {
        // バイナリが見つからない場合も、起動自体は open 経路で試みる。
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                return (0, "", "")
            },
            kittenPathProvider: { nil })
        let outcome = try launcher.launch(terminal: .kitty, command: "echo hi")
        XCTAssertEqual(outcome, .window)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].first, "/usr/bin/open")
    }

    func test_kitty_throws_when_open_fails() {
        // Kitty 未インストール等、タブ経路と open 経路の両方が失敗した場合。
        var received: [[String]] = []
        let launcher = TerminalLauncher(
            runCommand: { args in
                received.append(args)
                return (1, "", "Unable to find application named 'kitty'")
            },
            kittenPathProvider: { nil })
        XCTAssertThrowsError(try launcher.launch(terminal: .kitty, command: "echo hi")) { error in
            XCTAssertTrue((error as? TerminalLaunchError)?.message.contains("Kitty") == true,
                          "\(error)")
            XCTAssertTrue((error as? TerminalLaunchError)?.message.contains("Unable to find") == true,
                          "\(error)")
        }
        XCTAssertEqual(received.count, 1)
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
        // 既定の execute 実装（osascript 相当）を 1 秒で打ち切り、
        // exit 124 + タイムアウト文言を返すことを確認する。
        let (exit, stdout, stderr) = TerminalLauncher.execute(["-e", "delay 5"], timeout: 1)
        XCTAssertEqual(exit, 124, stderr)
        XCTAssertTrue(stderr.contains("タイムアウト"), stderr)
        _ = stdout
    }

    func test_execute_returns_fast_for_short_script() {
        let (exit, _, stderr) = TerminalLauncher.execute(["-e", "return 0"], timeout: 5)
        XCTAssertEqual(exit, 0, stderr)
    }

    // MARK: herdr（Issue #130）

    /// herdr の do / open 呼び出しを差し替えるファクトリ。
    /// - commandProbe: 起動コマンド（[herdr-app, do, tab.new, payload] の形式）を
    ///   受け取り、(exit, stdout, stderr) を返す。
    private func makeLauncher(
        herdrBinary: String?,
        workingDirectory: String? = nil,
        openSucceeds: Bool = true,
        windowLaunchTimeout: TimeInterval? = nil,
        commandProbe: @escaping ([String]) -> (Int32, String, String)
    ) -> TerminalLauncher {
        TerminalLauncher(
            runCommand: { command in
                if command.first == "/usr/bin/open" {
                    return openSucceeds ? (0, "", "") : (1, "", "Unable to find application")
                }
                return commandProbe(command)
            },
            herdrBinaryProvider: { herdrBinary },
            herdrWorkingDirectoryProvider: { workingDirectory ?? "/fallback/cwd" },
            herdrWindowLaunchTimeout: windowLaunchTimeout
        )
    }

    func test_herdr_shell_argv_wraps_command_in_login_shell() {
        let argv = ResumeCommand.herdrShellArgv(command: "cd '/tmp' && moost resume s1")
        XCTAssertEqual(argv, ["/bin/zsh", "-lc", "cd '/tmp' && moost resume s1"])
    }

    func test_herdr_folder_extracts_cd_path() {
        let cmd = "cd '/Users/dev/my app' && moost resume s1 --agent claude"
        XCTAssertEqual(TerminalLauncher.herdrFolder(for: cmd, fallback: "/fb"),
                       "/Users/dev/my app")
    }

    func test_herdr_folder_keeps_separator_inside_quotes() {
        // 名前に " && " を含むパスは閉じ引用符までがトークン。
        let cmd = "cd '/tmp/a && b' && moost resume s1"
        XCTAssertEqual(TerminalLauncher.herdrFolder(for: cmd, fallback: "/fb"), "/tmp/a && b")
    }

    func test_herdr_folder_falls_back_when_no_cd() {
        XCTAssertEqual(TerminalLauncher.herdrFolder(for: "moost resume s1", fallback: "/fb"), "/fb")
        // 引用符が閉じていない壊れたコマンドもフォールバック。
        XCTAssertEqual(TerminalLauncher.herdrFolder(for: "cd '/oops && x", fallback: "/fb"), "/fb")
    }

    func test_unquote_roundtrips_shell_escaped_path() {
        // shellEscape の '\'' 形式を復元できる（Support.swift の shellEscape と対）。
        XCTAssertEqual(TerminalLauncher.unquote("'it'\\''s here'"), "it's here")
        XCTAssertEqual(TerminalLauncher.unquote("/plain"), "/plain")
    }

    func test_herdr_tab_new_payload_shape() {
        let json = TerminalLauncher.herdrTabNewPayload(
            folder: "/tmp dir",
            argv: ["/bin/zsh", "-lc", "cd '/tmp dir' && echo \"hi\""],
            name: "moost:resume"
        )
        // herdr-app do に渡す単一 JSON 文字列（focus:false / folder / argv / name）。
        // 文字列一致は引用符まで含む完全一致で確認する（エスケープ事故を
        // 緩い contains で見過ごさない）。
        XCTAssertTrue(json.hasPrefix("{"), json)
        XCTAssertTrue(json.contains("\"focus\":false"), json)
        XCTAssertTrue(json.contains("\"folder\":"), json) // 値の完全一致は下の JSON 往査で検証
        XCTAssertTrue(json.contains("\"name\":\"moost:resume\""), json)
        XCTAssertTrue(json.contains("echo \\\"hi\\\""), json) // 参照先の引用符は JSON で \" にエスケープ
        // 必ず JSON として読めること（エスケープ事故防止の担保）。
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["focus"] as? Bool, false)
        XCTAssertEqual(obj["folder"] as? String, "/tmp dir")
        XCTAssertEqual(obj["name"] as? String, "moost:resume")
        XCTAssertEqual(obj["argv"] as? [String], ["/bin/zsh", "-lc", "cd '/tmp dir' && echo \"hi\""])
    }

    func test_herdr_do_result_parses_success_terminal_id() {
        let ok: (Int32, String, String) =
            (0, "{\"space\":\"s1\",\"tab\":\"tb1\",\"terminal\":\"t9\"}", "")
        XCTAssertEqual(TerminalLauncher.herdrDoResult(ok), .success(terminal: "t9"))
    }

    func test_herdr_do_result_failure_shapes() {
        // 未起動は exit 2 + プレインテキスト。
        let sock: (Int32, String, String) = (2, "", "could not connect to socket")
        if case .failure = TerminalLauncher.herdrDoResult(sock) {} else {
            XCTFail("exit 2 must be failure")
        }
        // spawn 失敗は exit 1 + JSON error。
        let spawn: (Int32, String, String) =
            (1, "{\"error\":\"failed to spawn process: No such file or directory (os error 2)\"}", "")
        if case .failure = TerminalLauncher.herdrDoResult(spawn) {} else {
            XCTFail("spawn error must be failure")
        }
        // exit 0 でも terminal キーが無ければ失敗（空オブジェクト対策）。
        let empty: (Int32, String, String) = (0, "{}", "")
        if case .failure = TerminalLauncher.herdrDoResult(empty) {} else {
            XCTFail("empty object must be failure")
        }
        // 空 stdout / 非 JSON も失敗。
        let blank: (Int32, String, String) = (0, "", "")
        if case .failure = TerminalLauncher.herdrDoResult(blank) {} else {
            XCTFail("blank stdout must be failure")
        }
    }

    func test_herdr_launch_uses_do_tab_new_with_payload() throws {
        var seen: [[String]] = []
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app") { command in
            seen.append(command)
            return (0, "{\"space\":\"s1\",\"tab\":\"tb1\",\"terminal\":\"t9\"}", "")
        }
        let outcome = try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/Users/dev/my app' && moost resume s1 --agent claude")
        XCTAssertEqual(outcome, TerminalLaunchOutcome.background(terminal: "t9"))
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0][0], "/usr/local/bin/herdr-app")
        XCTAssertEqual(seen[0][1], "do")
        XCTAssertEqual(seen[0][2], "tab.new")
        let payload = try XCTUnwrap(seen[0].last)
        let obj = try JSONSerialization.jsonObject(with: payload.data(using: .utf8)!)
            as! [String: Any]
        XCTAssertEqual(obj["focus"] as? Bool, false)
        XCTAssertEqual(obj["folder"] as? String, "/Users/dev/my app")
        XCTAssertEqual(obj["name"] as? String, TerminalLauncher.herdrResumeTabName)
        XCTAssertEqual(obj["argv"] as? [String],
                       ["/bin/zsh", "-lc", "cd '/Users/dev/my app' && moost resume s1 --agent claude"])
    }

    func test_herdr_launch_opens_app_and_retries_on_socket_error() throws {
        var seen: [[String]] = []
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app") { command in
            seen.append(command)
            if seen.count == 1 { return (2, "", "could not connect to socket") }
            return (0, "{\"space\":\"s1\",\"tab\":\"tb1\",\"terminal\":\"t10\"}", "")
        }
        let outcome = try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/tmp' && moost resume s1")
        XCTAssertEqual(outcome, TerminalLaunchOutcome.background(terminal: "t10"))
        XCTAssertEqual(seen.count, 2, "open 後に do を再試行する")
        XCTAssertEqual(seen[0][1...2], ["do", "tab.new"])
    }

    func test_herdr_launch_stops_early_on_identical_retry_responses() throws {
        // 未起動相当（exit 2 同一応答）が続く場合、deadline まで叩かず
        // 同一応答 3 回連続で打ち切る（初回 1 + リトライ 3）。
        // 失敗理由は最後のリトライ結果（reason 文が空にならない）。
        var probed = 0
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app",
                                    windowLaunchTimeout: 8) { _ in
            probed += 1
            return (2, "", "could not connect to socket")
        }
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/tmp' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(error.message.contains("could not connect to socket"), error.message)
        }
        XCTAssertEqual(probed, 4, "同一応答 3 回連続で早期打ち切り（初回+リトライ3回）")
    }

    func test_herdr_launch_stops_early_on_empty_object_spawn_failure() throws {
        // spawn 失敗が `{}` exit 0 で返るケース: open は走るが、同一応答の
        // リトライを deadline（約32回）まで繰り返さず早期打ち切りする。
        var probed = 0
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app",
                                    windowLaunchTimeout: 8) { _ in
            probed += 1
            return (0, "{}", "")
        }
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/nope' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(error.message.contains("Herdr"), error.message)
            XCTAssertFalse(error.message.hasSuffix("（）"),
                           "失敗理由が空になっていないこと: \(error.message)")
        }
        XCTAssertLessThan(probed, 10, "{} 固定応答で deadline まで叩かない: probed=\(probed)")
        XCTAssertEqual(probed, 4)
    }

    func test_herdr_launch_retry_loop_is_cut_by_deadline() throws {
        // timeout 注入の実使用確認: 応答が毎回変わる（同一応答打ち切り不发動）
        // でも deadline で打ち切られる。0.6 秒 ⇒ 0.25 秒間隔ならリトライは
        // 多くて 2 回（総 do 呼び出しは初回+2 以下）。
        var probed = 0
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app",
                                    windowLaunchTimeout: 0.6) { _ in
            probed += 1
            return (2, "", "socket wait \(probed)") // 毎回変わる = 連続同一応答にならない
        }
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/tmp' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            // 最後のリトライ結果が理由に入ること（lastFailure が最終試行であること）。
            XCTAssertTrue(error.message.contains("socket wait \(probed)"), error.message)
        }
        XCTAssertLessThanOrEqual(probed, 3, "deadline で打ち切られる: probed=\(probed)")
        XCTAssertGreaterThanOrEqual(probed, 2)
    }

    func test_herdr_launch_does_not_open_app_on_spawn_error() throws {
        // exit 1 + JSON error（folder 不正等の spawn 失敗）は open せず即失敗。
        var probed = 0
        var opened = false
        let launcher = TerminalLauncher(
            runCommand: { command in
                if command.first == "/usr/bin/open" {
                    opened = true
                    return (0, "", "")
                }
                probed += 1
                return (1, "{\"error\":\"failed to spawn process: boom\"}", "")
            },
            herdrBinaryProvider: { "/usr/local/bin/herdr-app" },
            herdrWorkingDirectoryProvider: { "/fallback/cwd" }
        )
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/nope' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            let message = error.message
            XCTAssertTrue(message.contains("Herdr"), message)
            XCTAssertTrue(message.contains("boom"), message)
        }
        XCTAssertEqual(probed, 1, "spawn 失敗で do を繰り返さない")
        XCTAssertFalse(opened, "spawn 失敗では open しない")
    }

    func test_herdr_launch_throws_when_binary_missing() {
        let launcher = makeLauncher(herdrBinary: nil) { _ in (0, "{}", "") }
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/tmp' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            let message = error.message
            // 開き方を教える文言（UI がそのままトーストへ出す）。
            XCTAssertTrue(message.contains("Herdr"), message)
        }
    }

    func test_herdr_launch_gives_up_when_open_fails() {
        // 初回 do 失敗（未起動）→ open 失敗 → 再試行せず例外（open の理由も含む）。
        var probed = 0
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app",
                                    openSucceeds: false) { _ in
            probed += 1
            return (2, "", "could not connect to socket")
        }
        XCTAssertThrowsError(try launcher.launch(terminal: TerminalApp.herdr, command: "cd '/tmp' && moost resume s1")) { error in
            guard let error = error as? TerminalLaunchError else {
                return XCTFail("unexpected error: \(error)")
            }
            let message = error.message
            XCTAssertTrue(message.contains("could not connect to socket"), message)
            XCTAssertTrue(message.contains("Unable to find application"), message)
        }
        XCTAssertEqual(probed, 1, "open 失敗後は do を再試行しない")
    }

    func test_herdr_launch_falls_back_to_working_directory_without_cd() throws {
        // codex の projectPath 空セッションのように cd が読めないコマンドは
        // 注入した workingDirectory を folder に使う。
        var seen: [[String]] = []
        let launcher = makeLauncher(herdrBinary: "/usr/local/bin/herdr-app",
                                    workingDirectory: "/Users/dev/work") { command in
            seen.append(command)
            return (0, "{\"space\":\"s1\",\"tab\":\"tb1\",\"terminal\":\"t11\"}", "")
        }
        _ = try launcher.launch(terminal: TerminalApp.herdr, command: "moost resume s1")
        let payload = try XCTUnwrap(seen.last?.last)
        let obj = try JSONSerialization.jsonObject(with: payload.data(using: .utf8)!)
            as! [String: Any]
        XCTAssertEqual(obj["folder"] as? String, "/Users/dev/work")
    }

}
