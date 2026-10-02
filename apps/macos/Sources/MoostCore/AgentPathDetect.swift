import Foundation

/// claude / codex コマンドの検出（design.md 7 章【1】GUI の PATH 問題）。
/// 順序: 設定の手動上書き（`~` 展開）→ 既知パス → 対話シェルの whence。
/// リファレンス実装:
/// - packages/core/lib/src/agent/claude_code/claude_path_resolver.dart
/// - packages/core/lib/src/agent/codex/codex_path_resolver.dart
///
/// GUI アプリから起動すると PATH が最小限になり bare なコマンドが解決
/// できないため、3 段構えで解決する。シェルは `-lic`（対話ログインシェル）
/// を付けて .zshrc/.bashrc を読ませる（Issue #53）。
public enum AgentPathDetect {
    public static func claude(override: String = "") -> String? {
        detect(override: override, command: "claude", knownPaths: claudeKnownPaths())
    }

    public static func codex(override: String = "") -> String? {
        detect(override: override, command: "codex", knownPaths: codexKnownPaths())
    }

    private static func claudeKnownPaths() -> [String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.local/bin/claude",
            home + "/bin/claude",
            "/usr/bin/claude",
        ]
    }

    private static func codexKnownPaths() -> [String] {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home + "/.local/bin/codex",
            home + "/bin/codex",
        ]
    }

    private static func detect(override: String, command: String, knownPaths: [String]) -> String? {
        if !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            return nil // 上書き指定は検出結果より優先され、見つからなければ「なし」
        }

        for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // GUI 起動では PATH が最小限のため、対話シェルの検索を最後に試す
        return whenceViaLoginShell(command)
    }

    /// Linux では zsh が無いことが多いため bash を使う（GUI から起動するため
    /// PATH が最小限になる問題はどちらの OS でも同じ）。
    private static func whenceViaLoginShell(_ command: String) -> String? {
        #if os(Linux)
        let shell = "/bin/bash"
        let flags = ["-ic"]
        #else
        let shell = "/bin/zsh"
        let flags = ["-lic"]
        #endif
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell, isDirectory: false)
        process.arguments = flags + ["command -v " + command]
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let path = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }
            // 末尾改行を除いた最終行だけを実行結果として採用する
            // （.zshrc 内の echo 等の出力が混ざることがあるため）
            return path
        } catch {
            return nil
        }
    }
}
