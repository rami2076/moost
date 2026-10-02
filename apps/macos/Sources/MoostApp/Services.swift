import AppKit
import Foundation
import ServiceManagement

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
