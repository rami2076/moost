import Foundation

/// アプリ全体の公示値（bundle を持たない SPM 実行ファイルのため定数で持つ）。
public enum AppInfo {
    /// SwiftPM 実行時のバージョン。cask 本線切替（フェーズ C）で実値に差し替える。
    public static let version = "2.0.0-dev"
    public static let popoverSize = NSSize(width: 570, height: 660)
}
