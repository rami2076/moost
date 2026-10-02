import AppKit
import Foundation
import ServiceManagement

/// claude コマンドの検出（design.md 7 章【1】GUI の PATH 問題）。
/// 順序: 設定の手動上書き（`~` 展開）→ 既知パス → 対話シェルの whence。
enum ClaudePathDetect {
    static func detect(override: String) -> String? {
        if !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            return nil // 上書き指定は検出結果より優先され、見つからなければ「なし」
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let known = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.local/bin/claude",
            "/usr/bin/claude",
        ]
        for path in known where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // GUI 起動では PATH が最小限のため、対話シェルの検索を最後に試す
        return whenceViaLoginShell()
    }

    private static func whenceViaLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh", isDirectory: false)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let path = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }
            return path
        } catch {
            return nil
        }
    }
}

/// ログイン時自動起動（design.md 6.6）。
/// 設定ストアに持たず OS（SMAppService）の実状態を正とし、毎回読む。
/// SPM 実行ファイル（bundle なし）では登録に失敗しうるため、呼び出し側で
/// エラーを表示して実状態へ戻す。
enum AutoLaunchService {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// `moost mcp` の CLI サブコマンド（アプリ内蔵 MCP サーバー、stdio JSON-RPC）。
/// Node 前提にしない。実装は第 3 インクリメント（Main.swift の方針を引き継ぐ）。
enum MCPServerCLI {
    static func run() {
        fputs("moost mcp: 実装は第 3 インクリメントで対応予定です（#78 の残タスク）。\n", stderr)
        exit(0)
    }
}

/// 表示用の日時・パス整形（画面共通の小さなユーティリティ）。
enum AppFormat {
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
