import Foundation

/// 人が読める JSON ファイルの読み取り基盤（A1-A3）。
/// リファレンス実装: packages/core/lib/src/store/json_file_store.dart
///
/// - A1 書き込みは Data.write(options: .atomic)（一時ファイル → リネーム）
/// - A2 破損時は上書きせず `<name>.corrupt-<timestamp>` へ退避して nil を返す
/// - A3 読み取りエラー（権限等）は握りつぶさず throw する。存在しないだけ nil
public final class JsonFileStore {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func load() throws -> [String: Any]? {
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            let nsError = error as NSError
            let isMissing = (nsError.domain == NSCocoaErrorDomain && nsError.code == 260)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 2)
            if isMissing { return nil }
            throw error
        }
        do {
            let decoded = try MoostJSON.parse(text)
            guard let dictionary = decoded as? [String: Any] else {
                try quarantine()
                return nil
            }
            return dictionary
        } catch {
            if case MoostError.malformedJSON = error {
                try quarantine()
                return nil
            }
            throw error
        }
    }

    /// 生 JSON 文字列をそのままアトミックに書き込む（A1）。
    public func saveRaw(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var payload = text
        payload.unicodeScalars.append(Unicode.Scalar(0x0a))
        try Data(payload.utf8).write(to: file, options: .atomic)
    }
    public func save(_ json: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = MoostJSON.serialize(json, pretty: true) + "\n"
        try Data(text.utf8).write(to: file, options: .atomic)
    }

    private func quarantine() throws {
        let stamp = ISOUTC.format(Date()).replacingOccurrences(of: ":", with: "-")
        try FileManager.default.moveItem(
            at: file, to: URL(fileURLWithPath: file.path + ".corrupt-" + stamp, isDirectory: false))
    }
}

/// `~/.moost/v2/memos.json` の CRUD（B1-B3）。リファレンス実装: memo_store.dart
public final class MemoStore {
    public static let schemaVersion = 1
    private let store: JsonFileStore

    public init(file: URL) {
        store = JsonFileStore(file: file)
    }

    /// native 世代の保存先（~/.moost/v2/memos.json）。v1 からの移行は DataMigration を参照
    public static func defaultLocation() -> MemoStore {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return MemoStore(file: URL(fileURLWithPath: home + "/.moost/v2/memos.json", isDirectory: false))
    }

    public func load() throws -> [Memo] {
        guard let json = try store.load() else { return [] }
        guard let rawMemos = json["memos"] as? [Any] else { return [] }
        var memos: [Memo] = []
        for raw in rawMemos {
            guard let map = raw as? [String: Any] else { continue }
            // 壊れた 1 件のためにストア全体を捨てない（B3）
            if let memo = try? Memo.fromJson(map) {
                memos.append(memo)
            }
        }
        return memos
    }

    public func add(_ memo: Memo) throws {
        var memos = try load()
        memos.append(memo)
        try save(memos)
    }

    /// 可変フィールド（title / tags / body）だけを更新する（B4）。
    public func update(_ id: String, title: String? = nil, tags: [String]? = nil,
                       body: String? = nil) throws -> Bool {
        var memos = try load()
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return false }
        memos[index] = memos[index].updateUserFields(
            title: title, tags: tags, body: body, updatedAt: Date())
        try save(memos)
        return true
    }

    public func delete(_ id: String) throws -> Bool {
        var memos = try load()
        let before = memos.count
        memos.removeAll { $0.id == id }
        guard memos.count != before else { return false }
        try save(memos)
        return true
    }

    private func save(_ memos: [Memo]) throws {
        // Any 橋渡しを経ない専用経路（リテラルの [String: Any] は使わない）
        try store.saveRaw(MoostJSON.envelope(
            schemaVersion: Self.schemaVersion,
            key: "\u{6d}\u{65}\u{6d}\u{6f}\u{73}",
            items: memos.map { $0.jsonText() }))
    }
}

/// アプリ設定（C1-C3）。リファレンス実装: settings_store.dart
/// 型が違う項目は その項目だけ デフォルトへフォールバックする（落とさない）。
public struct Settings: Equatable {
    public var terminalApp = "Terminal.app"
    public var recentSessionLimit = 20
    public var claudePath = ""
    public var summaryRallyCount = 1
    public var copyAnimation = true
    /// pi 起動時に指定する provider 名（空なら付けない）。Issue #68。
    public var piProvider = ""
    /// pi 起動時に指定する model 名（空なら付けない）。Issue #68。
    public var piModel = ""

    public init() {}
}

public final class SettingsStore {
    public static let schemaVersion = 1
    private let store: JsonFileStore

    public init(file: URL) {
        store = JsonFileStore(file: file)
    }

    public static func defaultLocation() -> SettingsStore {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return SettingsStore(file: URL(fileURLWithPath: home + "/.moost/v2/settings.json", isDirectory: false))
    }

    public func load() throws -> Settings {
        var settings = Settings()
        // 存在チェック・破損退避は JsonFileStore の契約（A2/A3）と同じ足取り
        guard try store.load() != nil else { return settings }
        let text: String
        do {
            text = try String(contentsOf: store.file, encoding: .utf8)
        } catch {
            let nsError = error as NSError
            if nsError.code == 260 || nsError.code == 2 { return settings } // 存在しないのみ
            throw error
        }
        if let value = JsonScalar.string(text, "terminalApp") { settings.terminalApp = value }
        if let value = JsonScalar.integer(text, "recentSessionLimit") { settings.recentSessionLimit = value }
        if let value = JsonScalar.string(text, "claudePath") { settings.claudePath = value }
        if let value = JsonScalar.integer(text, "summaryRallyCount") { settings.summaryRallyCount = value }
        if let value = JsonScalar.boolean(text, "copyAnimation") { settings.copyAnimation = value }
        if let value = JsonScalar.string(text, "piProvider") { settings.piProvider = value }
        if let value = JsonScalar.string(text, "piModel") { settings.piModel = value }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try store.save([
            "schemaVersion": Self.schemaVersion,
            "terminalApp": settings.terminalApp,
            "recentSessionLimit": settings.recentSessionLimit,
            "claudePath": settings.claudePath,
            "summaryRallyCount": settings.summaryRallyCount,
            "copyAnimation": settings.copyAnimation,
            "piProvider": settings.piProvider,
            "piModel": settings.piModel,
        ])
    }
}

/// v1（Flutter 世代）→ v2（native 世代）の初回起動時移行。
/// 移行後も `~/.moost/v1/` は読み取り専用で保存されるため復元可能（7.5 復旧対応）。
public enum DataMigration {
    private static let files = ["memos.json", "settings.json", "projects.json"]

    /// v2 を新設し v1 からコピーして完了マーカーを打つ。作業を行った場合は true を返す。
    @discardableResult
    public static func migrateIfNeeded(homeDirectoryPath home: String = ProcessInfo.processInfo.environment["HOME"] ?? "") throws -> Bool {
        let fileManager = FileManager.default
        let v2 = URL(fileURLWithPath: home + "/.moost/v2", isDirectory: true)
        let v1 = URL(fileURLWithPath: home + "/.moost/v1", isDirectory: true)
        let marker = v2.appendingPathComponent(".migrated-from-v1")

        if fileManager.fileExists(atPath: marker.path) { return false }
        let hasV1 = fileManager.fileExists(atPath: v1.path + "/memos.json")
            || fileManager.fileExists(atPath: v1.path + "/settings.json")
            || fileManager.fileExists(atPath: v1.path + "/projects.json")

        try fileManager.createDirectory(at: v2, withIntermediateDirectories: true)
        var didWork = false
        if hasV1 && !fileManager.fileExists(atPath: marker.path) {
            for name in files {
                let source = v1.appendingPathComponent(name)
                let target = v2.appendingPathComponent(name)
                // 既存の v2 ファイルは上書きしない（後の世代を優先する）
                if fileManager.fileExists(atPath: target.path) { continue }
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: target)
                    didWork = true
                }
            }
        }
        try Data().write(to: marker)
        return didWork
    }
}

/// `~/.moost/v2/projects.json` の読み取り（D1-D3）。リファレンス実装: project_store.dart
/// displayName は保存せず projectPath から導出しする（D2）。壊れた 1 件はスキップ（D3）。
public final class ProjectStore {
    public static let schemaVersion = 1
    private let store: JsonFileStore

    public init(file: URL) {
        store = JsonFileStore(file: file)
    }

    public static func defaultLocation() -> ProjectStore {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return ProjectStore(file: URL(fileURLWithPath: home + "/.moost/v2/projects.json", isDirectory: false))
    }

    public func load() throws -> [Project] {
        guard let json = try store.load() else { return [] }
        guard let rawProjects = json["projects"] as? [Any] else { return [] }
        var projects: [Project] = []
        for raw in rawProjects {
            guard let map = raw as? [String: Any] else { continue }
            // 1 件 malformed を全体障害と混同しない（design.md 7 章）
            if let project = try? Project.fromJson(map) {
                projects.append(project)
            }
        }
        return projects
    }

    public func save(_ projects: [Project]) throws {
        try store.saveRaw(MoostJSON.envelope(
            schemaVersion: Self.schemaVersion,
            key: "\u{70}\u{72}\u{6f}\u{6a}\u{65}\u{63}\u{74}\u{73}",
            items: projects.map { $0.jsonText() }))
    }
}
