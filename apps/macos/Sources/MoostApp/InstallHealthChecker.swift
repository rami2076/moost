import Foundation

/// 中断された brew アップグレードによるインストール破損の検知
/// （Flutter 版 install_health_checker.dart の native 移植。Issue #58）。
///
/// - 実体がないのに Caskroom にレコードだけ残った状態（`*.upgrading` の残骸）
/// - `/Applications/Moost.app` の実行ファイルが存在しない（途中で削除された）
///
/// のいずれかを「破損」と判定する。判定は同期・軽量なのでいつ呼んでもよい。
/// ただし**修復は必ず brew 経由**（`brew reinstall --cask moost`）になるため、
/// brew 管理下（Caskroom にレコードあり）でない手動導入時は破損と見なさない
/// （Flutter 版は実行ファイル欠落を常に破損扱いだが、手動導入には修復手段が
/// なく、開発環境の誤検知にもつながるため native 版では brew 管理下に限定する）。
enum InstallHealthChecker {
    static let appExecutablePath = "/Applications/Moost.app/Contents/MacOS/MoostApp"
    static let caskroomDirs = [
        "/opt/homebrew/Caskroom/moost",
        "/usr/local/Caskroom/moost",
    ]

    /// brew でインストールされているか（Caskroom にレコードがあるか）。
    static var isBrewManaged: Bool {
        caskroomDirs.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// true なら「修復」フローを案内する（Flutter 版 isInstallBroken に相当）。
    static func isBroken() -> Bool {
        guard isBrewManaged else { return false }
        let fm = FileManager.default
        if !fm.fileExists(atPath: appExecutablePath) {
            return true
        }
        for dir in caskroomDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if entries.contains(where: { $0.hasSuffix(".upgrading") }) {
                return true
            }
        }
        return false
    }
}
