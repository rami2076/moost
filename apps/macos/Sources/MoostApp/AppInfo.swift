import Foundation

/// アプリ全体の公示値（bundle を持たない SPM 実行ファイルのため定数で持つ）。
public enum AppInfo {
    /// SemVer 本体（プラットフォーム共通。リリースごとに上げる）。
    public static let version = "2.0.0"

    /// プラットフォーム識別子。git タグ・アセット名・brew cask の version に使う
    /// （macos / linux / windows。フェーズ D（#73）で linux / windows が増える）。
    public static let platformTag: String = {
        #if os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #else
        return "windows"
        #endif
    }()

    /// 表示・タグ・配布物に使う完全版（例: `2.0.0-macos`）。
    /// `--version` と MCP serverInfo.version にもこの値を出す。
    public static var displayVersion: String { "\(version)-\(platformTag)" }

    public static let popoverSize = NSSize(width: 570, height: 660)
}
