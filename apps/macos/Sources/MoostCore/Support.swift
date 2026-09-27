import Foundation

public enum MoostError: Error {
    case malformedMemo([String: Any])
    case malformedProject([String: Any])
    case malformedJSON(String)
}

/// UTC ISO8601（`2026-09-20T09:00:00.000Z` 形式）の書式。リファレンス実装の
/// `toUtc().toIso8601String()` との相互運用が可能（B6）。
public enum ISOUTC {
    private static func make(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .iso8601)
        return formatter
    }
    private static let withFraction = make("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private static let plain = make("yyyy-MM-dd'T'HH:mm:ss'Z'")

    public static func format(_ date: Date) -> String { withFraction.string(from: date) }

    /// 生成側は .SSS 付きだが、読み取り側は秒精度までからも受理する（寛容性）。
    public static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

/// epoch 秒/ミリ秒から Date を作る（1970 基準の初期化をラップする）。
extension Date {
    init(ms: Double) {
        self.init(timeIntervalSince1970: ms / 1000)
    }
    init(seconds: Double) {
        self.init(timeIntervalSince1970: seconds)
    }
    var ms: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}

/// POSIX シェル向けに文字列をシングルクォートでエスケープする（G1）。
/// リファレンス実装 shell_escape.dart と同形（design.md 7 章ハマりどころ 4）。
public func shellEscape(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// settings.json のような小ファイルは、NSNumber 橋渡しに頼らず生テキストで型を
/// 判定する（Dart の `value is num && value is! bool` 相当の語義）。
public enum JsonScalar {
    public static func string(_ text: String, _ key: String) -> String? {
        capture(text, "\"" + key + "\"\\s*:\\s*\"([^\"]*)\"")
    }
    public static func integer(_ text: String, _ key: String) -> Int? {
        capture(text, "\"" + key + "\"\\s*:\\s*(-?[0-9]+)(?![.0-9])").flatMap(Int.init)
    }
    public static func boolean(_ text: String, _ key: String) -> Bool? {
        if capture(text, "\"" + key + "\"\\s*:\\s*true(?![A-Za-z])") != nil { return true }
        if capture(text, "\"" + key + "\"\\s*:\\s*false(?![A-Za-z])") != nil { return false }
        return nil
    }
    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: full) else { return nil }
        let slice = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard slice.location != NSNotFound, let swiftRange = Range(slice, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}

/// Foundation の JSON 系 API に依存しない、契約専用の小さなパーサ／クリエイタ。
/// データ契約の適合判定はこの单一の実装と spec/testdata の Fixture が担う。
public enum MoostJSON {
    public static func parse(_ text: String) throws -> Any {
        var parser = JSONParser(chars: Array(text))
        parser.skipWhitespaces()
        guard parser.hasRemaining else {
            parser.note("\u{65}\u{6d}\u{70}\u{74}\u{79}\u{20}\u{69}\u{6e}\u{70}\u{75}\u{74}")
            throw MoostError.malformedJSON(parser.joinedNotes())
        }
        let value = try parser.parseValue()
        parser.skipWhitespaces()
        guard !parser.hasRemaining else {
            parser.note("\u{74}\u{72}\u{61}\u{69}\u{6c}\u{69}\u{6e}\u{67}\u{20}\u{61}\u{74}\u{20}" + String(parser.pos) + "\u{20}\u{7c}\u{20}" + parser.snippet())
            throw MoostError.malformedJSON(parser.joinedNotes())
        }
        guard parser.notes.isEmpty else {
            throw MoostError.malformedJSON(parser.joinedNotes())
        }
        return value
    }

    /// 型付きの値だけを扱う直结 JSON 生成。[String: Any] のリテラル生成を經ない
    /// 永続経路はこちらを使う（Any への橋渡しで生じる型崩れの影響を受けない）。
    public static func value(_ text: String) -> String { jsonString(text) }

    public static func value(_ number: Int) -> String { String(number) }

    public static func value(_ flag: Bool) -> String { flag ? "\u{74}\u{72}\u{75}\u{65}" : "\u{66}\u{61}\u{6c}\u{73}\u{65}" }

    public static func value(_ items: [String]) -> String {
        if items.isEmpty { return "\u{5b}\u{5d}" }
        return "\u{5b}" + items.map { jsonString($0) }.joined(separator: "\u{2c}") + "\u{5d}"
    }

    /// キー順を保证したオブジェクト（呼び出し側の並び順のママ）。
    public static func object(_ members: [(String, String)]) -> String {
        if members.isEmpty { return "\u{7b}\u{7d}" }
        return "\u{7b}" + members.map { jsonString($0.0) + "\u{3a}" + $0.1 }
            .joined(separator: "\u{2c}") + "\u{7d}"
    }

    /// `{"schemaVersion": n, "<key>": [...]}` のエンベローラ（B1 / D1）。
    /// items は jsonObject() が返す生 JSON 文字列を受け取る。
    /// `{"schemaVersion": n, "<key>": [...]}` のエンベローラ（B1 / D1）。
    /// items は jsonObject() が返す生 JSON 文字列を受け取る。
    public static func envelope(schemaVersion: Int, key: String, items: [String]) -> String {
        let head = jsonString("schemaVersion") + "\u{3a}" + String(schemaVersion) + "\u{2c}"
        let body = jsonString(key) + "\u{3a}" + array(items)
        return "\u{7b}" + head + body + "\u{7d}"
    }

    /// 生 JSON 文字列の配列をつなぐ（items が 0 件でも [] を返す）。
    public static func array(_ items: [String]) -> String {
        if items.isEmpty { return "\u{5b}\u{5d}" }
        return "\u{5b}" + items.joined(separator: "\u{2c}") + "\u{5d}"
    }
    public static func serialize(_ value: Any, pretty: Bool = true) -> String {
        func enc(_ v: Any, _ depth: Int) -> String {
            let indent = pretty ? String(repeating: "  ", count: depth + 1) : ""
            let close = pretty ? String(repeating: "  ", count: depth) : ""
            let nl = pretty ? "\n" : ""
            let colon = pretty ? ": " : ":"
            switch v {
            case let b as Bool: return b ? "true" : "false"
            case let i as Int: return String(i)
            case let d as Double: return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
            case is NSNull: return "null"
            case let s as String: return jsonString(s)
            case let arr as [Any]:
                if arr.isEmpty { return "[]" }
                return "[" + nl + arr.map { indent + enc($0, depth + 1) }.joined(separator: "," + nl) + nl + close + "]"
            case let dict as [String: Any]:
                let keys = dict.keys.sorted()
                if keys.isEmpty { return "{}" }
                return "{" + nl + keys.map { indent + jsonString($0) + colon + enc(dict[$0]!, depth + 1) }
                    .joined(separator: "," + nl) + nl + close + "}"
            default: return jsonString(String(describing: v))
            }
        }
        return enc(value, 0)
    }

    static func jsonString(_ s: String) -> String {
        var out = "\u{22}"
        for ch in s.unicodeScalars {
            let code = Int(ch.value)
            switch code {
            case 34: out += "\u{5c}\u{22}"
            case 92: out += "\u{5c}\u{5c}"
            case 10: out += "\u{5c}\u{6e}"
            case 13: out += "\u{5c}\u{72}"
            case 9: out += "\u{5c}\u{74}"
            case 8: out += "\u{5c}\u{62}"
            case 12: out += "\u{5c}\u{66}"
            default:
                if code < 0x20 {
                    out.unicodeScalars.append(contentsOf: [Unicode.Scalar(92), Unicode.Scalar(117)])
                    out += String(format: "\u{25}\u{34}\u{78}", code)
                } else {
                    out.unicodeScalars.append(contentsOf: [ch])
                }
            }
        }
        out += "\u{22}"
        return out
    }
}


private struct JSONParser {
    var notes: [String] = []
    let chars: [Character]
    var pos = 0
    var hasRemaining: Bool { pos < chars.count }
    var current: Character? { pos < chars.count ? chars[pos] : nil }

    mutating func skipWhitespaces() {
        while let ch = current, ch == " " || ch == "\t" || ch == "\n" || ch == "\r" { pos += 1 }
    }

    mutating func expect(_ word: String) throws {
        for ch in word {
            guard current == ch else {
            note("\u{65}\u{78}\u{70}\u{65}\u{63}\u{74}\u{20}" + word + "\u{20}\u{61}\u{74}\u{20}" + String(pos) + "\u{20}\u{7c}\u{20}" + snippet())
            throw MoostError.malformedJSON(joinedNotes())
            }
            pos += 1
        }
    }

    func joinedNotes() -> String {
        notes.joined(separator: "\u{20}\u{3b}\u{20}")
    }

    func snippet() -> String {
        var out = ""
        var index = pos
        while index < chars.count && out.count < 24 {
            let ch = chars[index]
            if ch == "\u{22}" { break }
            out += String(ch)
            index += 1
        }
        return out
    }

    mutating func note(_ message: String) {
        notes.append(message)
    }
    static func isNumberStart(_ ch: Character) -> Bool {
        let value = ch.unicodeScalars.first?.value ?? 0
        return (value >= 0x30 && value <= 0x39) || value == 0x2d || value == 0x2b || value == 0x2e
    }

    mutating func parseValue() throws -> Any {
        guard let ch = current else {
            note("\u{6e}\u{6f}\u{20}\u{76}\u{61}\u{6c}\u{75}\u{65}\u{20}\u{61}\u{74}\u{20}" + String(pos))
            throw MoostError.malformedJSON(joinedNotes())
        }
        switch ch {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return try parseString()
        case "t": try expect("true"); return true
        case "f": try expect("false"); return false
        case "n": try expect("null"); return NSNull()
        default:
            guard Self.isNumberStart(ch) else {
            note("\u{76}\u{61}\u{6c}\u{75}\u{65}\u{20}\u{61}\u{74}\u{20}" + String(pos) + "\u{20}\u{7c}\u{20}" + snippet())
            throw MoostError.malformedJSON(joinedNotes())
            }
            return try parseNumber()
        }
    }

    mutating func parseObject() throws -> [String: Any] {
        var out: [String: Any] = [:]
        try expect("{")
        skipWhitespaces()
        if current == "}" { pos += 1; return out }
        var keepGoing = true
        while keepGoing {
            skipWhitespaces()
            let key = try parseString()
            skipWhitespaces()
            try expect(":")
            skipWhitespaces()
            out[key] = try parseValue()
            skipWhitespaces()
            if current == "," { pos += 1; continue }
            try expect("}")
            keepGoing = false
        }
        return out
    }

    mutating func parseArray() throws -> [Any] {
        var out: [Any] = []
        try expect("[")
        skipWhitespaces()
        if current == "]" { pos += 1; return out }
        var keepGoing = true
        while keepGoing {
            skipWhitespaces()
            out.append(try parseValue())
            skipWhitespaces()
            if current == "," { pos += 1; continue }
            try expect("]")
            keepGoing = false
        }
        return out
    }

    mutating func parseNumber() throws -> Any {
        var token = ""
        if current == "-" { token.append("-"); pos += 1 }
        var isFloat = false
        while let ch = current {
            let isDigit = ch >= "0" && ch <= "9"
            let isExp = ch == "e" || ch == "E"
            let isSign = (ch == "+" || ch == "-") && (token.last == "e" || token.last == "E")
            if isDigit || isExp || isSign {
                token.append(ch); pos += 1
            } else if ch == "." && token.last != "." {
                isFloat = true; token.append(ch); pos += 1
            } else {
                break
            }
        }
        if !isFloat, let i = Int(token) { return i }
        if let d = Double(token) { return d }
        throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}")
    }

    mutating func parseString() throws -> String {
        try expect("\"")
        var out: [Unicode.Scalar] = []
        while let ch = current {
            pos += 1
            if ch == "\"" { var text = "" ; text.unicodeScalars.append(contentsOf: out); return text }
            guard ch == "\\" else { out.append(ch.unicodeScalars.first!); continue }
            guard let esc = current else { throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}") }
            pos += 1
            switch esc {
            case "\u{22}": out.append("\u{22}".unicodeScalars.first!)
            case "\u{5c}": out.append("\u{5c}".unicodeScalars.first!)
            case "\u{2f}": out.append("\u{2f}".unicodeScalars.first!)
            case "\u{72}": out.append("\u{d}".unicodeScalars.first!)
            case "\u{6e}": out.append("\u{a}".unicodeScalars.first!)
            case "\u{74}": out.append("\u{9}".unicodeScalars.first!)
            case "\u{62}": out.append("\u{8}".unicodeScalars.first!)
            case "\u{66}": out.append("\u{c}".unicodeScalars.first!)
            case "\u{75}":
                var code = 0
                for _ in 0..<4 {
                    guard let h = current else { throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}") }
                    let digit = try hexValue(h); code = code * 16 + digit; pos += 1
                }
                out.append(Unicode.Scalar(code) ?? Unicode.Scalar(65533)!)
            default: throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}")
            }
        }
        throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}")
    }

    func hexValue(_ ch: Character) throws -> Int {
        guard let scalar = ch.unicodeScalars.first else { throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}") }
        switch scalar {
        case "0"..."9": return Int(scalar.value) - Int(Unicode.Scalar(0x30)!.value)
        case "a"..."f": return Int(scalar.value) - Int(Unicode.Scalar(0x61)!.value) + 10
        case "A"..."F": return Int(scalar.value) - Int(Unicode.Scalar(0x41)!.value) + 10
        default: throw MoostError.malformedJSON("\u{69}\u{6e}\u{76}\u{61}\u{6c}\u{69}\u{64}\u{20}\u{4a}\u{53}\u{4f}\u{4e}")
        }
    }
}
