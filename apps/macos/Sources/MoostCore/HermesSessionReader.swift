import Foundation
import SQLite3

/// sqlite3_bind_text のデストラクタ指定（SQLITE_TRANSIENT）。C のマクロは
/// Swift から見えないため unsafeBitCast で作り直す。
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Hermes（Nous Research の自律エージェント、`hermes` CLI）のセッション読み取り。
///
/// Hermes は `~/.hermes/state.db`（SQLite, WAL）に全会話を保存する
/// （`~/.hermes/sessions/` は空。v0.22.3 実機確認）。
/// Moost はこの DB を**読み取り専用**で開き、`sessions` / `messages` テーブルから
/// 一覧・最終プロンプト・会話抜粋を取る。書き込みは一切しない。
///
/// - 一覧対象: `source IN ('local','oneshot')`（CLI 起点のセッション）かつ
///   `message_count > 0`（起動スタブ除外、`hermes -c` の `skip_launch_stubs` と同じ発想）
///   - gateway / acp 起点は v1 では除外（端末で復帰する想定の CLI セッションのみ）
/// - アーカイブ・非表示は除外（`archived` / `hidden`）
/// - 復帰は `hermes chat --resume <id>`（`--resume latest` や `--continue` は Moost では使わない）

/// Hermes セッション 1 件分の抽出結果。
public struct HermesSessionEntry: Equatable, Sendable {
    public let sessionId: String
    public let projectPath: String
    public let lastPrompt: String
    public let updatedAt: Date
    public let aiTitle: String?

    public init(sessionId: String, projectPath: String,
                lastPrompt: String, updatedAt: Date, aiTitle: String? = nil) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.lastPrompt = lastPrompt
        self.updatedAt = updatedAt
        self.aiTitle = aiTitle
    }
}

/// state.db 読み取りの失敗。呼び出し側（SessionAggregator）では
/// 他のエージェントと同様「空扱い」にされるため、UI に直接出ない。
public enum HermesStateError: Error, Equatable, Sendable {
    case openFailed(String)
    case queryFailed(String)
}

/// Hermes セッション一覧の読み取り。
/// リファレンス実装: hermes-agent v0.22.3 の `SessionDB.search_sessions`
/// （`gateway_session_store.py`）。
public final class HermesSessionReader: Sendable {
    public let dbURL: URL

    public init(dbURL: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.dbURL = dbURL ?? URL(fileURLWithPath: home + "/.hermes/state.db")
    }

    /// 一覧を新しい順で返す。DB が存在しなければ空（他のエージェントの
    /// 「未インストール」と同じ扱い）。
    public func recentSessions(limit: Int = 20) throws -> [HermesSessionEntry] {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return []
        }
        let db = try HermesStateDB.open(path: dbURL.path)
        defer { db.close() }

        // 最終利用時刻がなければ開始時刻。source は CLI 起点だけ、
        // メッセージが 1 件もない起動スタブは除外する。
        let rows = try db.prepare("""
            SELECT id, COALESCE(title, ''), COALESCE(cwd, ''),
                   COALESCE(last_activity_at, started_at)
            FROM sessions
            WHERE source IN ('local', 'oneshot')
              AND message_count > 0
              AND COALESCE(archived, 0) = 0
              AND COALESCE(hidden, 0) = 0
            ORDER BY COALESCE(last_activity_at, started_at) DESC
            LIMIT ?
            """) { stmt in
            sqlite3_bind_int64(stmt, 1, Int64(limit))
        } rows: { stmt in
            HermesSessionRow(
                id: HermesStateDB.text(stmt, 0),
                title: HermesStateDB.text(stmt, 1),
                cwd: HermesStateDB.text(stmt, 2),
                activity: HermesStateDB.double(stmt, 3))
        }

        var out: [HermesSessionEntry] = []
        for row in rows {
            // 最終プロンプト = 最後のユーザー発言（title は AI 生成の表題として別途保持）
            let lastUser = try db.prepare("""
                SELECT content FROM messages
                WHERE session_id = ? AND role = 'user'
                  AND length(trim(COALESCE(content, ''))) > 0
                ORDER BY timestamp DESC, id DESC
                LIMIT 1
                """) { stmt in
                sqlite3_bind_text(stmt, 1, row.id, -1, sqliteTransient)
            } rows: { stmt in
                HermesStateDB.text(stmt, 0)
            }
            out.append(HermesSessionEntry(
                sessionId: row.id,
                projectPath: row.cwd,
                lastPrompt: lastUser.first ?? row.title,
                updatedAt: Date(seconds: row.activity),
                aiTitle: row.title.isEmpty ? nil : row.title))
        }
        return Array(out.prefix(limit))
    }

    private struct HermesSessionRow {
        let id: String
        let title: String
        let cwd: String
        let activity: Double
    }
}

/// Hermes セッションの会話抜粋（要約用テキスト）を作る。
/// Hermes はヘッドレス要約コマンドを持たないため、抽出結果をそのまま
/// 要約として返す（pi と同じ方針、API 消費ゼロ）。
public final class HermesTranscriptExtractor: Sendable {
    public let dbURL: URL

    public init(dbURL: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.dbURL = dbURL ?? URL(fileURLWithPath: home + "/.hermes/state.db")
    }

    /// セッション [sessionId] のやり取りをテキスト化して返す。
    /// DB が無い・セッションが無い場合は空文字列。
    /// - full が false: 末尾 rallies ラリー（ユーザー発言 1 つ + 続く応答群）
    /// - full が true: セッション全体
    public func extract(sessionId: String, full: Bool = false, rallies: Int = 1) -> String {
        guard FileManager.default.fileExists(atPath: dbURL.path),
              let db = try? HermesStateDB.open(path: dbURL.path)
        else { return "" }
        defer { db.close() }

        let rows: [HermesMessageRow]
        do {
            rows = try db.prepare("""
                SELECT role, COALESCE(content, ''), COALESCE(tool_name, '')
                FROM messages
                WHERE session_id = ? AND COALESCE(active, 1) = 1
                ORDER BY timestamp ASC, id ASC
                """) { stmt in
                sqlite3_bind_text(stmt, 1, sessionId, -1, sqliteTransient)
            } rows: { stmt in
                HermesMessageRow(
                    role: HermesStateDB.text(stmt, 0),
                    content: HermesStateDB.text(stmt, 1),
                    toolName: HermesStateDB.text(stmt, 2))
            }
        } catch {
            return ""
        }
        guard !rows.isEmpty else { return "" }

        // ラリーのまとまりを作る（Claude / Codex エクストラクタと同じ足取り）
        var collected: [HermesRally] = []
        for row in rows {
            switch row.role {
            case "user":
                let text = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                collected.append(HermesRally(userText: text))
                if !full && collected.count > rallies {
                    // メモリを抑えるため保持は直近分だけにする
                    collected.removeFirst()
                }
            case "assistant":
                let text = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !collected.isEmpty else { continue }
                collected[collected.count - 1].followups.append(.assistant(text))
            case "tool":
                guard !collected.isEmpty else { continue }
                let output = toolOutput(row.content)
                guard !output.isEmpty else { continue }
                collected[collected.count - 1].followups.append(.tool(row.toolName, output))
            default:
                continue
            }
        }
        guard !collected.isEmpty else { return "" }
        return render(collected)
    }

    /// tool 行の content（JSON: `{"output": ..., "exit_code": ...}`）から出力を取り出す。
    private func toolOutput(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let decoded = (try? MoostJSON.parse(trimmed)) as? [String: Any],
           let output = decoded["output"] as? String {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // JSON でない場合は raw のまま（出力の一部として扱う）
        return trimmed
    }

    private func render(_ rallies: [HermesRally]) -> String {
        var buffer = ""
        for rally in rallies {
            buffer += "User: \(rally.userText)\n"
            for followup in rally.followups {
                switch followup {
                case .assistant(let text):
                    buffer += "Assistant: \(text)\n"
                case .tool(let name, let output):
                    let label = name.isEmpty ? "tool" : name
                    buffer += "Tool(\(label)): \(output)\n"
                }
            }
            buffer += "\n"
        }
        return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum Followup {
        case assistant(String)
        case tool(String, String)
    }

    private struct HermesRally {
        let userText: String
        var followups: [Followup] = []
    }

    private struct HermesMessageRow {
        let role: String
        let content: String
        let toolName: String
    }
}

/// state.db への読み取り専用 SQLite 接続（Moost 内部用）。
private final class HermesStateDB {
    private var handle: OpaquePointer?

    static func open(path: String) throws -> HermesStateDB {
        let db = HermesStateDB()
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &db.handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = db.handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db.handle)
            db.handle = nil
            throw HermesStateError.openFailed(message)
        }
        return db
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }

    /// SQL を実行して各行を [T] に変換して返す。bind でプレースホルダに値を設定する。
    func prepare<T>(
        _ sql: String,
        bind: (OpaquePointer?) -> Void,
        rows transform: (OpaquePointer?) -> T
    ) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesStateError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)

        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(transform(stmt))
        }
        return out
    }

    static func text(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    static func double(_ stmt: OpaquePointer?, _ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }
}
