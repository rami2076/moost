import Foundation

/// モデルの読み取りと適合に関する規約（リファレンス実装: packages/core/lib/src/model/）

public struct Memo: Equatable, Sendable {
    public let id: String
    public let agent: String
    public let sessionId: String
    public let title: String
    public let tags: [String]
    public let body: String
    public let projectPath: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, agent: String, sessionId: String, title: String,
                tags: [String], body: String, projectPath: String,
                createdAt: Date, updatedAt: Date) {
        self.id = id
        self.agent = agent
        self.sessionId = sessionId
        self.title = title
        self.tags = tags
        self.body = body
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 永続向けの生 JSON 文字列。`[String: Any]` のリテラル生成を經ない。
    func jsonText() -> String {
        MoostJSON.object([
            ("\u{69}\u{64}", MoostJSON.value(id)),
            ("\u{61}\u{67}\u{65}\u{6e}\u{74}", MoostJSON.value(agent)),
            ("\u{73}\u{65}\u{73}\u{73}\u{69}\u{6f}\u{6e}\u{49}\u{64}", MoostJSON.value(sessionId)),
            ("\u{74}\u{69}\u{74}\u{6c}\u{65}", MoostJSON.value(title)),
            ("\u{74}\u{61}\u{67}\u{73}", MoostJSON.value(tags)),
            ("\u{62}\u{6f}\u{64}\u{79}", MoostJSON.value(body)),
            ("\u{70}\u{72}\u{6f}\u{6a}\u{65}\u{63}\u{74}\u{50}\u{61}\u{74}\u{68}", MoostJSON.value(projectPath)),
            ("\u{63}\u{72}\u{65}\u{61}\u{74}\u{65}\u{64}\u{41}\u{74}", MoostJSON.value(ISOUTC.format(createdAt))),
            ("\u{75}\u{70}\u{64}\u{61}\u{74}\u{65}\u{64}\u{41}\u{74}", MoostJSON.value(ISOUTC.format(updatedAt))),
        ])
    }
    /// 可変フィールド（title / tags / body）だけを差し替えたコピーを返す。
    /// updatedAt は必ず更新される（ADR-003）。
    public func updateUserFields(title: String? = nil, tags: [String]? = nil,
                                 body: String? = nil, updatedAt: Date) -> Memo {
        Memo(id: id, agent: agent, sessionId: sessionId,
             title: title ?? self.title,
             tags: tags ?? self.tags,
             body: body ?? self.body,
             projectPath: projectPath,
             createdAt: createdAt, updatedAt: updatedAt)
    }

    public func toJson() -> [String: Any] {
        ["id": id, "agent": agent, "sessionId": sessionId, "title": title,
         "tags": tags, "body": body, "projectPath": projectPath,
         "createdAt": ISOUTC.format(createdAt), "updatedAt": ISOUTC.format(updatedAt)]
    }

    public static func fromJson(_ json: [String: Any]) throws -> Memo {
        guard let id = json["id"] as? String,
              let agent = json["agent"] as? String,
              let sessionId = json["sessionId"] as? String,
              let title = json["title"] as? String,
              let rawTags = json["tags"] as? [Any],
              let tags = rawTags as? [String],
              let body = json["body"] as? String,
              let projectPath = json["projectPath"] as? String,
              let createdAtString = json["createdAt"] as? String,
              let createdAt = ISOUTC.parse(createdAtString),
              let updatedAtString = json["updatedAt"] as? String,
              let updatedAt = ISOUTC.parse(updatedAtString) else {
            throw MoostError.malformedMemo(json)
        }
        return Memo(id: id, agent: agent, sessionId: sessionId, title: title,
                    tags: tags, body: body, projectPath: projectPath,
                    createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// カンマ区切りのタグ入力を分割・トリム・空要素除去して配列にする。
public func parseTags(_ input: String) -> [String] {
    input.components(separatedBy: ",")
         .map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty }
}

public struct Project: Equatable, Sendable {
    public let id: String
    public let projectPath: String
    public let createdAt: Date

    public init(id: String, projectPath: String, createdAt: Date) {
        self.id = id
        self.projectPath = projectPath
        self.createdAt = createdAt
    }

    /// 一覧表示用の名前。projectPath の最後のディレクトリ名を都度導出しする（保存はしない）。
    public var displayName: String {
        var trimmed = projectPath
        if trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        let segment = trimmed.components(separatedBy: "/").last.map { String($0) } ?? ""
        return segment.isEmpty ? projectPath : segment
    }

    public func toJson() -> [String: Any] {
        ["id": id, "projectPath": projectPath, "createdAt": ISOUTC.format(createdAt)]
    }

    /// 永続向けの生 JSON 文字列（D1）。
    func jsonText() -> String {
        MoostJSON.object([
            ("\u{69}\u{64}", MoostJSON.value(id)),
            ("\u{70}\u{72}\u{6f}\u{6a}\u{65}\u{63}\u{74}\u{50}\u{61}\u{74}\u{68}", MoostJSON.value(projectPath)),
            ("\u{63}\u{72}\u{65}\u{61}\u{74}\u{65}\u{64}\u{41}\u{74}", MoostJSON.value(ISOUTC.format(createdAt))),
        ])
    }

    public static func fromJson(_ json: [String: Any]) throws -> Project {
        guard let id = json["id"] as? String,
              let projectPath = json["projectPath"] as? String,
              let createdAtString = json["createdAt"] as? String,
              let createdAt = ISOUTC.parse(createdAtString) else {
            throw MoostError.malformedMemo(json)
        }
        return Project(id: id, projectPath: projectPath, createdAt: createdAt)
    }
}

public struct RecentSession: Equatable, Sendable {
    public let agentId: String
    public let sessionId: String
    public let projectPath: String
    public let lastPrompt: String
    public let updatedAt: Date
    public let aiTitle: String?

    public init(agentId: String, sessionId: String, projectPath: String,
                lastPrompt: String, updatedAt: Date, aiTitle: String? = nil) {
        self.agentId = agentId
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.lastPrompt = lastPrompt
        self.updatedAt = updatedAt
        self.aiTitle = aiTitle
    }

    static let fallbackTitleLength = 50

    /// セッションタイトル。ai-title があればそれ、なければ最終プロンプト先頭 50 文字。
    /// グラフェクラ単位で数えるのでサロゲートペアの分断をしない。
    public var displayTitle: String {
        if let title = aiTitle, !title.isEmpty {
            return title
        }
        let characters = Array(lastPrompt)
        if characters.count <= Self.fallbackTitleLength {
            return lastPrompt
        }
        return String(characters.prefix(Self.fallbackTitleLength))
    }

    public func withAiTitle(_ aiTitle: String?) -> RecentSession {
        RecentSession(agentId: agentId, sessionId: sessionId, projectPath: projectPath,
                      lastPrompt: lastPrompt, updatedAt: updatedAt, aiTitle: aiTitle)
    }
}
