import Foundation

/// MCP 設定の登録・解除・自己診断（Issue #45 の Dart 実装 `McpSetupService` の移植）。
///
/// アプリ内蔵 MCP サーバー（`<MoostApp> mcp`）を Claude Code / Codex CLI /
/// Claude Desktop / Hermes / Zed へワンクリックで連携登録する。
///
/// - Claude Code / Codex CLI は `<cli> mcp add` / `mcp remove` / `mcp get`
///   サブコマンドを使う（`mcp get` の終了コードで登録済みか判定）。
/// - Claude Desktop は CLI サブコマンドが無いため、設定 JSON
///   `~/Library/Application Support/Claude/claude_desktop_config.json` の
///   `mcpServers.moost` キーだけをマージする（他社製 MCP サーバーの
///   設定は壊さない。既存キーは保持する）。
/// - Hermes（Issue #132）は CLI（`hermes mcp add/remove`）が接続テストと削除時に
///   対話プロンプトを持つため非対話では使えない。Hermes 本体が保存するのと
///   同じ形のエントリを `~/.hermes/config.yaml` の `mcp_servers.moost` キーへ
///   YAML ブロック単位の行レベルマージで挿入／削除する（コメント・他の節・
///   他サーバー定義の行は一切書き換えない）。
/// - Zed（Issue #132）は `~/.config/zed/settings.json` の
///   `context_servers.moost` キーだけをマージする（Zed の MCP サーバー設定の
///   正式キーは `context_servers`。zed.dev/docs/ai/mcp 確認済み）。
///   settings.json は JSONC（コメント可）のため、パースはコメント除去 +
///   trailing comma 除去で行い、書き戻しは**コメントを保持しない**
///   （Issue #132 で明示的に合意した妥協。UI と CHANGELOG にも明記）。
///   既存のキー・値は保持し、壊れた JSONC は例外にして上書きしない。
///
/// バイナリのパスは配布形態（.app 同梱 / 開発ビルド）で異なるため、
/// 呼び出し側（App 層）が実行中バイナリのパスを解決して渡す。
public enum McpSetupError: Error, Equatable {
    case commandNotFound(String)
    case processFailed(String)
    case invalidJson(String)
}

public struct McpSetupService: Sendable {
    /// 外部コマンド実行の結果（テストで差し替え可能）。
    public typealias Runner = @Sendable (String, [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)

    private let runner: Runner
    private let claudeOverride: String
    private let codexOverride: String
    private let hermesOverride: String
    private let claudeDesktopConfigPath: String
    private let hermesConfigPath: String
    private let zedSettingsPath: String

    public init(
        runner: Runner? = nil,
        claudeOverride: String = "",
        codexOverride: String = "",
        hermesOverride: String = "",
        home: String? = nil,
        claudeDesktopConfigPath: String? = nil,
        hermesConfigPath: String? = nil,
        zedSettingsPath: String? = nil
    ) {
        let homeValue = home ?? ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.runner = runner ?? McpSetupService.defaultRunner
        self.claudeOverride = claudeOverride
        self.codexOverride = codexOverride
        self.hermesOverride = hermesOverride
        self.claudeDesktopConfigPath = claudeDesktopConfigPath
            ?? homeValue + "/Library/Application Support/Claude/claude_desktop_config.json"
        self.hermesConfigPath = hermesConfigPath ?? homeValue + "/.hermes/config.yaml"
        self.zedSettingsPath = zedSettingsPath ?? homeValue + "/.config/zed/settings.json"
    }

    /// プロセスを起動して終了コードと標準出力を取る既定実装。
    public static func defaultRunner(_ executable: String, _ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do {
            try p.run()
        } catch {
            throw McpSetupError.processFailed("failed to start \(executable): \(error.localizedDescription)")
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (
            p.terminationStatus,
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    // MARK: - Claude Code

    public func isClaudeCodeConnected() -> Bool {
        guard let claude = AgentPathDetect.claude(override: claudeOverride) else { return false }
        guard let result = try? runner(claude, ["mcp", "get", "moost"]) else { return false }
        return result.exitCode == 0
    }

    public func registerClaudeCode(binaryPath: String) throws {
        let claude = try requireClaude()
        try runOrThrow(claude, ["mcp", "add", "-s", "user", "moost", "--"] + [binaryPath, "mcp"])
    }

    public func unregisterClaudeCode() throws {
        let claude = try requireClaude()
        try runOrThrow(claude, ["mcp", "remove", "moost", "-s", "user"])
    }

    // MARK: - Codex CLI

    public func isCodexConnected() -> Bool {
        guard let codex = AgentPathDetect.codex(override: codexOverride) else { return false }
        guard let result = try? runner(codex, ["mcp", "get", "moost"]) else { return false }
        return result.exitCode == 0
    }

    public func registerCodex(binaryPath: String) throws {
        let codex = try requireCodex()
        try runOrThrow(codex, ["mcp", "add", "moost", "--"] + [binaryPath, "mcp"])
    }

    public func unregisterCodex() throws {
        let codex = try requireCodex()
        try runOrThrow(codex, ["mcp", "remove", "moost"])
    }

    // MARK: - Claude Desktop

    /// `claude_desktop_config.json` に `mcpServers.moost` キーが存在するか。
    public func isClaudeDesktopConnected() -> Bool {
        guard let config = try? readDesktopConfig() else { return false }
        guard let servers = config["mcpServers"] as? [String: Any] else { return false }
        return servers["moost"] != nil
    }

    /// `mcpServers.moost` だけを追記/更新する（他社製サーバーの設定は保持）。
    public func registerClaudeDesktop(binaryPath: String) throws {
        var config: [String: Any] = [:]
        if let existing = try readDesktopConfig() {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["moost"] = ["command": binaryPath, "args": ["mcp"]]
        config["mcpServers"] = servers
        try writeDesktopConfig(config)
    }

    /// `mcpServers.moost` キーだけを削除する（他社製サーバーの設定は保持）。
    public func unregisterClaudeDesktop() throws {
        guard let decoded = try? readDesktopConfig() else { return }
        guard var servers = decoded["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "moost")
        var config = decoded
        config["mcpServers"] = servers
        try writeDesktopConfig(config)
    }

    /// `hermesOverride` が空のときの hermes コマンド検出（UI のはじき出し用）。
    public func detectedHermesPath() -> String? {
        AgentPathDetect.hermes(override: hermesOverride)
    }

    // MARK: - Hermes（Issue #132）
    //
    // 設定先: `~/.hermes/config.yaml` の `mcp_servers` マッピング。
    // Hermes 公式 CLI（`hermes mcp add`）は登録時に stdio サーバーへ実接続テストを
    // 行い、失敗時に「Save config anyway?」、削除時に「Remove server?」と
    // 対話プロンプトを出す（v0.22.3 実機確認）ため、バックグラウンドからの
    // 非対話実行には使えない。そこで Hermes 本体の `hermes mcp add` が書くのと
    // 同じ形のエントリ（command / args / enabled）を config.yaml へ直接マージする
    // （Hermes 側は `load_config()` で読むだけなので等価。`/reload-mcp` または
    // 次セッションで読み込まれる）。
    //
    // マージ方式は「YAML ブロック単位の行レベル挿入／削除」:
    // `mcp_servers:` 節を探して `moost:` サブキーのブロックだけを挿入／置換／
    // 削除し、ファイルの他の行（コメント・他の節・他サーバー定義・クォート
    // 表記・並び順）は一切書き換えない（YAML ライブラリに依存しない）。
    // サブキーのインデントは既存節に追従する（既定 2 スペース）。

    /// `~/.hermes/config.yaml` の `mcp_servers.moost` が有効なサーバー定義か。
    /// コメントアウト（`# moost:`）や `enabled: false` は未登録とみなす。
    public func isHermesConnected() -> Bool {
        guard let text = try? readHermesConfig() else { return false }
        guard let range = hermesServersBlockRange(in: text) else { return false }
        let block = String(text[range])
        guard let indent = hermesServersKeyIndent(block) else { return false }
        guard let start = hermesServerEntryStart(of: "moost", indent: indent, in: block) else {
            return false
        }
        let end = hermesServerEntryEnd(after: start, indent: indent, in: block)
        let entry = String(block[start..<end])
        // enabled: false のエントリは Hermes が起動しない（未登録扱い）。
        for raw in entry.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("enabled:") {
                let value = t.dropFirst("enabled:".count)
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if value == "false" || value == "False" || value == "no" || value == "off" {
                    return false
                }
            }
        }
        return true
    }

    /// `mcp_servers.moost` だけを追記/更新する（他の節・他サーバーは保持）。
    public func registerHermes(binaryPath: String) throws {
        var text = (try? readHermesConfig()) ?? ""
        // 末尾改行が無ければ足しておく（ブロック挿入の前提）。
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // ファイル無し / 空: 最小の mcp_servers 節を作って登録。
            text = "mcp_servers:\n" + Self.hermesMoostEntry(indentUnit: "  ", binaryPath: binaryPath)
            try writeText(text, to: hermesConfigPath)
            return
        }

        if let range = hermesServersBlockRange(in: text) {
            var block = String(text[range])
            // 節が空（サブキー無し）でも登録できるよう、標準の 2 字インデントを既定にする。
            let indent = hermesServersKeyIndent(block) ?? "  "
            if let start = hermesServerEntryStart(of: "moost", indent: indent, in: block) {
                // 既存エントリはキー行を保持し、インデント付きの本体行だけを
                // 差し替える。ブロック全体への置換は先頭の「キー行直前の改行を
                // 含む 1 文字」を消してしまうため行構造を壊す。
                let bodyStart = block.index(after: block.index(ofNewlineOrEnd: start))
                let end = hermesServerEntryEnd(after: start, indent: indent, in: block)
                block.replaceSubrange(bodyStart..<end,
                                      with: Self.hermesMoostBody(indentUnit: indent, binaryPath: binaryPath))
            } else {
                // 節の末尾（末尾の空行・コメント行の直前）に挿入。
                let insertAt = hermesBlockInsertionPoint(in: block)
                block.insert(contentsOf: Self.hermesMoostEntry(indentUnit: indent, binaryPath: binaryPath),
                             at: insertAt)
            }
            text.replaceSubrange(range, with: block)
        } else {
            // 節そのものが無い: ファイル末尾に追記（他の内容は不変）。
            if !text.hasSuffix("\n") { text += "\n" }
            text += "mcp_servers:\n" + Self.hermesMoostEntry(indentUnit: "  ", binaryPath: binaryPath)
        }
        try writeText(text, to: hermesConfigPath)
    }

    /// `mcp_servers.moost` キーだけを削除する（他の節・他サーバーは保持）。
    /// ファイルが無い／節が無い／moost が無い場合は書き換えない。
    public func unregisterHermes() throws {
        guard var text = try? readHermesConfig() else { return }
        // 末尾改行の正規化（ブロック挿入・行走査の前提）。これにより
        // `hermesServersBlockRange` が節本体を正しく拾える。moost が無い場合は
        // 正規化だけ保存して終了する（削除処理は行わない）。
        let normalized = !text.isEmpty && !text.hasSuffix("\n")
        if normalized { text += "\n" }
        guard let range = hermesServersBlockRange(in: text) else {
            if normalized { try writeText(text, to: hermesConfigPath) }
            return
        }
        var block = String(text[range])
        let indent = hermesServersKeyIndent(block) ?? "  "
        guard let start = hermesServerEntryStart(of: "moost", indent: indent, in: block) else {
            if normalized { try writeText(text, to: hermesConfigPath) }
            return
        }
        let end = hermesServerEntryEnd(after: start, indent: indent, in: block)
        // キー行ごと削除する（キー行の 1 文字前 = 直前の改行は保持するので
        // 前後の行構造は保たれる）。
        block.replaceSubrange(start..<end, with: "")
        text.replaceSubrange(range, with: block)
        try writeText(text, to: hermesConfigPath)
    }

    /// `mcp_servers:` 節本体（キー行の直後〜次の「インデントなし」行の直前）の範囲。
    /// 節が存在しなければ nil。コメント行・空行は節の一部として含める。
    ///
    /// 節の終端は「インデントなしの内容行」で判定する。YAML はセクション内の
    /// 全キーがセクションキーより深いインデントを持つため、これは
    /// 「次のトップレベルキー」の判定と等価（行内コメント `a: b # x` のような
    /// コロン含みのコメント行を誤認しない）。
    ///
    /// 注意: 行走査は必ず `lineEnd` の **1 つ後ろ**（次の行頭）へ進めること。
    /// `lineEnd`（改行文字そのもの、または endIndex）を開始位置にすると、
    /// `index(ofNewlineOrEnd:)` が改行を「見つけた」位置を返して前へ進まず
    /// 無限ループする（#130 の CI flake で確認した教訓と同じ）。
    private func hermesServersBlockRange(in text: String) -> Range<String.Index>? {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text.index(ofNewlineOrEnd: lineStart)
            let line = String(text[lineStart..<lineEnd])
            if hermesIsServersKey(line) {
                var pos = lineEnd
                if pos < text.endIndex {
                    pos = text.index(after: pos)  // 改行をスキップして次の行頭へ
                }
                while pos < text.endIndex {
                    let nextEnd = text.index(ofNewlineOrEnd: pos)
                    let nextLine = String(text[pos..<nextEnd])
                    let trimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    let indented = nextLine.first == " " || nextLine.first == "\t"
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !indented {
                        break  // 次のトップレベルキー
                    }
                    if nextEnd == text.endIndex { return lineEnd..<text.endIndex }
                    pos = text.index(after: nextEnd)
                }
                return lineEnd..<pos
            }
            if lineEnd == text.endIndex { break }
            lineStart = text.index(after: lineEnd)
        }
        return nil
    }

    /// `mcp_servers:`（インデントなし・コメントでない）キー行か。
    private func hermesIsServersKey(_ line: String) -> Bool {
        if line.first == " " || line.first == "\t" || line.first == "#" { return false }
        guard line == "mcp_servers:" || line.hasPrefix("mcp_servers:") else { return false }
        // `mcp_servers: value` のようなインライン値はブロック形式でなく対象外。
        let rest = line.dropFirst("mcp_servers:".count)
        return rest.isEmpty || rest.first == "#"
    }

    /// 節本体先頭のサブキーのインデント文字列。節本体にサブキーが無ければ nil。
    /// 節本体はブロックの先頭行が空行（キー行の直後の改行の後ろが始まり）に
    /// なるため、最初の非空行で判定する。行頭がタブの行は YAML のインデント
    /// として不正なので対象外。
    private func hermesServersKeyIndent(_ block: String) -> String? {
        // 節本体の最初のサブキー行のインデントを返す。サブキーが無ければ nil
        // （= 空節。登録側は既定の 2 字インデントで書く）。
        guard let d = firstSubkeyDepth(in: block) else { return nil }
        return String(repeating: " ", count: d)
    }

    /// 行走査: `visit(lineStart, lineEnd)` を各行に対して呼び出す。
    /// `lineStart` は行頭、`lineEnd` は行末改行の位置（最終行で改行が無い場合は endIndex）。
    /// 各行の処理後、必ず改行の 1 つ後ろ（次の行頭）へ進むため無限ループしない。
    private func hermesForEachLine(in text: String, visit: (String.Index, String.Index) -> Bool) {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text.index(ofNewlineOrEnd: lineStart)
            if visit(lineStart, lineEnd) { return }
            if lineEnd == text.endIndex { return }
            lineStart = text.index(after: lineEnd)
        }
    }

    /// `lineStart..<lineEnd` が `count` 個のスペースでインデントされた先頭トークン
    /// （英数字・`_`・`-`・`.`・`/`・`@`）を返す。インデントが浅い/深い、タブ始まり、
    /// コメント行、先頭がトークン文字でない（`#`, `-`, `"` 等）場合は nil。
    /// 文字スカラーの直接比較だけで判定し、String 同士の比較や hasPrefix に頼らない。
    private func hermesKeyToken(lineStart: String.Index, lineEnd: String.Index,
                                indentCount: Int, in text: String) -> (token: String, colon: String.Index)? {
        var cur = lineStart
        var depth = 0
        while cur < lineEnd, text[cur] == " " {
            depth += 1
            cur = text.index(after: cur)
        }
        guard depth == indentCount, cur < lineEnd else { return nil }
        let isTokenChar: (Character) -> Bool = { c in
            return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9")
                || c == "_" || c == "-" || c == "." || c == "/" || c == "@"
        }
        guard isTokenChar(text[cur]) else { return nil }
        var tokenEnd = cur
        while tokenEnd < lineEnd, isTokenChar(text[tokenEnd]) {
            tokenEnd = text.index(after: tokenEnd)
        }
        guard tokenEnd < lineEnd, text[tokenEnd] == ":" else { return nil }
        return (String(text[cur..<tokenEnd]), tokenEnd)
    }

    /// 節ブロック内のサブキー行（セクションインデントちょうど深さの `key:` 行）を
    /// (キー名, 行頭位置) の列として列挙する。
    private func hermesTopLevelSubkeys(in block: String) -> [(name: String, lineStart: String.Index)] {
        var result: [(name: String, lineStart: String.Index)] = []
        guard let firstDepth = firstSubkeyDepth(in: block) else { return result }
        hermesForEachLine(in: block) { lineStart, lineEnd in
            if let key = hermesKeyToken(lineStart: lineStart, lineEnd: lineEnd,
                                        indentCount: firstDepth, in: block) {
                result.append((name: key.token, lineStart: lineStart))
            }
            return false
        }
        return result
    }

    /// 節本体の最初のサブキー行のインデント幅（スペース個数）。無ければ nil。
    private func firstSubkeyDepth(in block: String) -> Int? {
        // 最初の非空・非コメント行から推定: スペース数を見て、key: ならその深さ、
        // 深すぎ（入れ子）でも浅すぎ（セクションキー自体）でも候補にしないため、
        // key token 判定をそのまま使う。最初の key token 行の深さが節本体の深さ。
        var depth: Int?
        hermesForEachLine(in: block) { lineStart, lineEnd in
            let line = String(block[lineStart..<lineEnd])
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return false }
            // 深さに関係なく key token を取れた行の深さを返す（walk 停止）。
            var cur = lineStart
            var d = 0
            while cur < lineEnd, block[cur] == " " {
                d += 1
                cur = block.index(after: cur)
            }
            guard cur < lineEnd, block[cur] != "#", block[cur] != "\t" else { return true }
            depth = d
            return true
        }
        return depth
    }

    /// `indent` で始まる `<name>:` サブキー行（コメントでない）の開始位置。
    /// 見つからなければ nil。ブロックの先頭行が空行になるケース（キー行直後の
    /// 改行の後ろが始まり）も含めて全行を走査する。
    private func hermesServerEntryStart(of name: String, indent: String, in block: String) -> String.Index? {
        // 走査は文字単位・直接比較のみ（String 比較・hasPrefix・スライス比較に依存しない）。
        // 行頭からちょうど `indent.count` 個のスペース → 英字 → name の各文字一致 →
        // 次の文字が `:` または空白類 → コメントでない、の順で判定する。
        let want = indent.count
        let n = Array(name)
        guard !n.isEmpty else { return nil }
        var lineStart = block.startIndex
        while lineStart < block.endIndex {
            let lineEnd = block.index(ofNewlineOrEnd: lineStart)
            var cur = lineStart
            var depth = 0
            while cur < lineEnd, block[cur] == " " {
                depth += 1
                cur = block.index(after: cur)
            }
            var matched = depth == want && cur < lineEnd
            if matched {
                for ch in n {
                    if cur >= lineEnd || block[cur] != ch { matched = false; break }
                    cur = block.index(after: cur)
                }
            }
            if matched {
                if cur < lineEnd {
                    let c = block[cur]
                    matched = (c == ":") || (c == " ") || (c == "\t")
                } else {
                    matched = false
                }
            }
            if matched { return lineStart }
            if lineEnd == block.endIndex { break }
            lineStart = block.index(after: lineEnd)
        }
        return nil
    }

    /// エントリ末尾（同じ深さの次のサブキー、またはセクション末尾）の位置。
    /// `start` は `moost:` キー行の先頭。同じ深さの次のサブキー行の行頭を返し、
    /// 無ければブロック末尾（= セクション末尾）を返す。挿入・削除のどちらでも
    /// 前後の行構造を壊さない境界になる。
    private func hermesServerEntryEnd(after start: String.Index, indent: String, in block: String) -> String.Index {
        let want = indent.count
        var result = block.endIndex
        hermesForEachLine(in: block) { lineStart, lineEnd in
            guard lineStart > start else { return false }
            if hermesKeyToken(lineStart: lineStart, lineEnd: lineEnd,
                              indentCount: want, in: block) != nil {
                result = lineStart
                return true
            }
            return false
        }
        return result
    }

    /// ブロック末尾の挿入位置（末尾の連続コメント行・空行の直前）。
    /// 末尾の行が改行で終わっている場合はその **改行の後ろ**（＝新行の行頭）に
    /// 挿入する。`block.insert(contentsOf:)` は指定位置に「押し込む」ため、
    /// 改行より前（＝前の行の末尾）に挿入すると前の行に内容が merge してしまう。
    private func hermesBlockInsertionPoint(in block: String) -> String.Index {
        var lines: [(lineEnd: String.Index, blankOrComment: Bool)] = []
        hermesForEachLine(in: block) { lineStart, lineEnd in
            let line = String(block[lineStart..<lineEnd])
            let t = line.trimmingCharacters(in: .whitespaces)
            lines.append((lineEnd, t.isEmpty || t.hasPrefix("#")))
            return false
        }
        var insertIdx = lines.count
        while insertIdx > 0, lines[insertIdx - 1].blankOrComment {
            insertIdx -= 1
        }
        if insertIdx == 0 { return block.startIndex }
        let anchor = lines[insertIdx - 1].lineEnd
        if anchor < block.endIndex, block[anchor] == "\n" {
            return block.index(after: anchor)
        }
        return anchor
    }

    /// Hermes の `hermes mcp add` が保存する形と同じ stdio エントリ
    /// （hermes_cli/mcp_config.py の `_save_mcp_server` が書く key 集合:
    /// command / args / enabled。v0.22.3 実機 + ソース確認）。
    /// 値のクォートは JSON 表記（YAML のダブルクォート文字列と互換）。
    private static func hermesMoostEntry(indentUnit: String, binaryPath: String) -> String {
        return indentUnit + "moost:\n" + hermesMoostBody(indentUnit: indentUnit, binaryPath: binaryPath)
    }

    /// moost エントリの本体部分（キー行を除く command/args/enabled 3 行）。
    /// キー行保持の置換で使う。
    private static func hermesMoostBody(indentUnit: String, binaryPath: String) -> String {
        return indentUnit + "  command: " + McpYAML.quote(binaryPath) + "\n"
            + indentUnit + "  args: [\"mcp\"]\n"
            + indentUnit + "  enabled: true\n"
    }

    private func readHermesConfig() throws -> String {
        let url = URL(fileURLWithPath: hermesConfigPath)
        guard let data = try? Data(contentsOf: url) else {
            throw McpSetupError.processFailed("file not readable: \(hermesConfigPath)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw McpSetupError.invalidJson("\(hermesConfigPath) is not UTF-8")
        }
        return text
    }

    // MARK: - Zed（Issue #132）
    //
    // 設定先: `~/.config/zed/settings.json` の `context_servers` マッピング
    // （Zed の MCP サーバー設定のキーは `context_servers`。zed.dev/docs/ai/mcp
    // 確認済み。`mcp_servers` / `agent_servers` は MCP のキーではない）。
    //
    // settings.json は JSONC（// と /* */ のコメント、trailing comma を許容）。
    // パースはコメント除去 + trailing comma 除去 after MoostJSON.parse。
    // 書き戻しはパース→再シリアライズのためコメントは保持しない（Zed 既定の
    // ヘッダコメントが消える。UI と CHANGELOG に明記）。
    // 既存のキー・値（他の context_servers 定義を含む）は保持する。
    // パースできないファイルは例外を投げて上書きしない（安全側）。

    /// `settings.json` の `context_servers.moost` が存在し、`auto_disable` で
    /// 無効化されていなければ true。
    public func isZedConnected() -> Bool {
        guard let config = try? readZedSettings() else { return false }
        guard let servers = config["context_servers"] as? [String: Any] else { return false }
        guard let moost = servers["moost"] as? [String: Any] else { return false }
        if let flag = moost["auto_disable"] as? Bool, !flag { return false }
        return true
    }

    /// `context_servers.moost` だけを追記/更新する（他の設定キーは保持）。
    public func registerZed(binaryPath: String) throws {
        var config: [String: Any] = [:]
        if let existing = try readZedSettings() {
            config = existing
        }
        var servers = config["context_servers"] as? [String: Any] ?? [:]
        servers["moost"] = ["command": binaryPath, "args": ["mcp"]]
        config["context_servers"] = servers
        try writeZedSettings(config)
    }

    /// `context_servers.moost` キーだけを削除する（他の設定キーは保持）。
    public func unregisterZed() throws {
        guard var config = try? readZedSettings() else { return }
        guard var servers = config["context_servers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "moost")
        config["context_servers"] = servers
        try writeZedSettings(config)
    }

    /// JSONC を許容して settings.json を読む。壊れていれば invalidJson。
    private func readZedSettings() throws -> [String: Any]? {
        let url = URL(fileURLWithPath: zedSettingsPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let stripped = Self.stripJSONC(raw)
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let decoded = try? MoostJSON.parse(stripped) else {
            throw McpSetupError.invalidJson("\(zedSettingsPath) is not valid JSON/JSONC. Fix or remove it manually before retrying.")
        }
        guard let config = decoded as? [String: Any] else {
            throw McpSetupError.invalidJson("\(zedSettingsPath) does not contain a JSON object")
        }
        return config
    }

    private func writeZedSettings(_ config: [String: Any]) throws {
        let text = MoostJSON.serialize(config, pretty: true) + "\n"
        try writeText(text, to: zedSettingsPath)
    }

    /// JSONC → JSON。`//`・`/* */` コメントと trailing comma を除去する。
    /// 文字列リテラル内の `//` はコメント扱いしない（文字列内を素通りする）。
    /// Zed が受け付ける JSONC の実用範囲（エスケープ付き文字列・
    /// ネストコメントなし）に対応。
    static func stripJSONC(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        let chars = Array(input)
        var i = 0
        var inString = false
        while i < chars.count {
            let ch = chars[i]
            if inString {
                out.append(ch)
                if ch == "\\", i + 1 < chars.count {
                    out.append(chars[i + 1])
                    i += 2
                    continue
                }
                if ch == "\"" { inString = false }
                i += 1
                continue
            }
            if ch == "\"" {
                inString = true
                out.append(ch)
                i += 1
                continue
            }
            if ch == "/", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                    continue
                }
                if next == "*" {
                    i += 2
                    while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2
                    continue
                }
            }
            out.append(ch)
            i += 1
        }
        // trailing comma（, の後ろに空白を挟んで } または ]）を除去。
        var result = ""
        result.reserveCapacity(out.count)
        let cs = Array(out)
        var j = 0
        while j < cs.count {
            let ch = cs[j]
            if ch == "," {
                var k = j + 1
                while k < cs.count, cs[k] == " " || cs[k] == "\t" || cs[k] == "\n" || cs[k] == "\r" { k += 1 }
                if k < cs.count, cs[k] == "}" || cs[k] == "]" {
                    j += 1
                    continue
                }
            }
            result.append(ch)
            j += 1
        }
        return result
    }

    // MARK: - 自己診断

    /// `<binaryPath> mcp` を起動し initialize ハンドシェイクが通るかを確認する。
    public func selfTest(binaryPath: String, timeout: TimeInterval = 5) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["mcp"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardInput = stdinPipe
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do {
            try p.run()
        } catch {
            return false
        }
        let requestId = Int(Date().timeIntervalSince1970 * 1000)
        let request = "{\"jsonrpc\":\"2.0\",\"id\":\(requestId),\"method\":\"initialize\"," +
            "\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{}," +
            "\"clientInfo\":{\"name\":\"moost-selftest\",\"version\":\"1\"}}}\n"
        stdinPipe.fileHandleForWriting.write(Data(request.utf8))
        stdinPipe.fileHandleForWriting.closeFile()

        var found = false
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var buffer = Data()
            var found = false
        }
        let box = Box()
        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                semaphore.signal()
                return
            }
            box.buffer.append(data)
            guard let text = String(data: box.buffer, encoding: .utf8) else { return }
            if text.contains("\"id\":\(requestId)") && text.contains("\"result\"") {
                box.found = true
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        handle.readabilityHandler = nil
        if p.isRunning {
            p.terminate()
        }
        found = box.found
        return found
    }

    // MARK: - 内部

    private func requireClaude() throws -> String {
        guard let path = AgentPathDetect.claude(override: claudeOverride) else {
            throw McpSetupError.commandNotFound("claude command not found")
        }
        return path
    }

    private func requireCodex() throws -> String {
        guard let path = AgentPathDetect.codex(override: codexOverride) else {
            throw McpSetupError.commandNotFound("codex command not found")
        }
        return path
    }

    private func runOrThrow(_ executable: String, _ arguments: [String]) throws {
        let result: (exitCode: Int32, stdout: String, stderr: String)
        do {
            result = try runner(executable, arguments)
        } catch let error as McpSetupError {
            throw error
        } catch {
            throw McpSetupError.processFailed("failed to start \(executable): \(error.localizedDescription)")
        }
        if result.exitCode != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? result.stdout : result.stderr
            throw McpSetupError.processFailed(
                detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "exit code \(result.exitCode)" : detail)
        }
    }

    /// 設定ファイルを読む。ファイルが無い / 空の場合は nil。
    /// 壊れた JSON・オブジェクト以外の場合は invalidJson を投げる（上書きしない）。
    private func readDesktopConfig() throws -> [String: Any]? {
        let url = URL(fileURLWithPath: claudeDesktopConfigPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let decoded = try? MoostJSON.parse(text) else {
            throw McpSetupError.invalidJson("\(claudeDesktopConfigPath) is not valid JSON. Fix or remove it manually before retrying.")
        }
        guard let config = decoded as? [String: Any] else {
            throw McpSetupError.invalidJson("\(claudeDesktopConfigPath) does not contain a JSON object")
        }
        return config
    }

    private func writeDesktopConfig(_ config: [String: Any]) throws {
        let text = MoostJSON.serialize(config, pretty: true) + "\n"
        try writeText(text, to: claudeDesktopConfigPath)
    }

    /// 親ディレクトリを作ってアトミックに書き込む（5 設定先共通）。
    private func writeText(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw McpSetupError.processFailed("failed to write \(path): \(error.localizedDescription)")
        }
    }
}

/// 行単位ヘルパ（String.Index 版）。
private extension String {
    /// `from` 以降で最初の改行（無ければ endIndex）の位置を返す。
    func index(ofNewlineOrEnd from: Index) -> Index {
        var i = from
        while i < endIndex, self[i] != "\n" {
            i = index(after: i)
        }
        return i
    }
}

/// YAML スカラーのクォート（Hermes config.yaml 用）。JSON の文字列表記は
/// YAML のダブルクォート文字列（JSON 互換 escapes）としても妥当なので
/// MoostJSON のエスケープを流用する。
enum McpYAML {
    static func quote(_ s: String) -> String {
        MoostJSON.jsonString(s)
    }
}
