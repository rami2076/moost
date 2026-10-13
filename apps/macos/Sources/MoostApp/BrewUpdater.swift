import Foundation

/// brew 経由の自己更新・修復（Flutter 版 brew_updater.dart の native 移植）。
/// GUI アプリは PATH が最小限になるため、既知の絶対パス → zsh の 3 段構えで
/// brew のパスを解決する（AgentPathDetect と同じ方針）。
enum BrewUpdateError: LocalizedError {
    case brewNotFound
    case commandFailed(command: String, exitCode: Int32, detail: String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "brew コマンドが見つかりません"
        case .commandFailed(let command, let exitCode, let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) が exit \(exitCode) で失敗: \(trimmed)"
        }
    }
}

struct BrewPathResolver {
    static let knownAbsolutePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    /// brew の実行パス。見つからなければ nil。
    func resolve() -> String? {
        for path in Self.knownAbsolutePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // 最後の頼み: zsh のログイン環境から探す
        guard let output = runCapture("/bin/zsh", ["-lc", "command -v brew"]) else {
            return nil
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    func runCapture(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// テストで差し替えられるようにするためのプロトコル。
protocol BrewUpdating: Sendable {
    /// `brew update && brew upgrade --cask moost` を実行する。
    func run() async throws
    /// 中断されたアップグレードからの復旧（`brew reinstall --cask moost`）。
    func repair() async throws
}

/// `brew update && brew upgrade --cask moost` を実行する（Flutter 版 BrewUpdater の移植）。
///
/// 進捗は brew の CLI 出力に数値（%）が含まれないため取得できない。
/// 呼び出し側は不確定インジケーターで「実行中」だけを示す想定。
struct BrewUpdater: BrewUpdating {
    private let resolver: BrewPathResolver

    /// 壊れて残った `/Applications/Moost.app` の削除を差し替え可能にする（テスト用）。
    var removeBrokenApp: @Sendable () -> Void

    init(
        resolver: BrewPathResolver = BrewPathResolver(),
        removeBrokenApp: @escaping @Sendable () -> Void = BrewUpdater.defaultRemoveBrokenApp
    ) {
        self.resolver = resolver
        self.removeBrokenApp = removeBrokenApp
    }

    static func defaultRemoveBrokenApp() {
        let url = URL(fileURLWithPath: "/Applications/Moost.app")
        try? FileManager.default.removeItem(at: url)
    }

    func run() async throws {
        let brew = try requireBrew()
        try await Self.runStep(brew, ["update"])
        try await Self.runStep(brew, ["upgrade", "--cask", "moost"])
    }

    /// 中断されたアップグレードで壊れた Caskroom 状態からの復旧（Issue #58）。
    /// `brew reinstall --cask moost` を試し、空になった `/Applications/Moost.app`
    /// が邪魔で失敗する場合はそれを取り除いて再試行する。
    func repair() async throws {
        let brew = try requireBrew()
        do {
            try await Self.runStep(brew, ["reinstall", "--cask", "moost"])
        } catch {
            removeBrokenApp()
            try await Self.runStep(brew, ["reinstall", "--cask", "moost"])
        }
    }

    private func requireBrew() throws -> String {
        guard let brew = resolver.resolve() else {
            throw BrewUpdateError.brewNotFound
        }
        return brew
    }

    /// 1 サブコマンドを実行して終了コードを検証する。
    /// Process の同期待ち（パイプ読み切り + waitUntilExit）はブロッキングなので
    /// 専用タスクに逃がしてから待つ。
    private static func runStep(_ brewPath: String, _ arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            try runStepSync(brewPath: brewPath, arguments: arguments)
        }.value
    }

    /// stdout / stderr は EOF まで読み切ってから終了を待つ
    /// （パイプバッファ詰まりの回避。claude_summarizer.dart と同理由）。
    private static func runStepSync(brewPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw BrewUpdateError.commandFailed(
                command: "brew \(arguments.joined(separator: " "))",
                exitCode: -1,
                detail: error.localizedDescription)
        }

        // パイプ詰まり回避のため stdio は専用スレッドで読み切る。
        let group = DispatchGroup()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        var stdoutData = Data()
        var stderrData = Data()
        let lock = NSLock()
        for handle in [stdoutHandle, stderrHandle] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                lock.lock()
                if handle === stdoutHandle { stdoutData = data } else { stderrData = data }
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        process.waitUntilExit()

        let exitCode = process.terminationStatus
        guard exitCode == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdout : stderr
            throw BrewUpdateError.commandFailed(
                command: "brew \(arguments.joined(separator: " "))",
                exitCode: exitCode,
                detail: detail)
        }
    }
}
