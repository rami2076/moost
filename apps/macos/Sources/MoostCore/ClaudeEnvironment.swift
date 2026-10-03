import Foundation

/// Claude Code が自身のプロセスに設定する内部環境変数の判定・除去
/// ユーティリティ（Issue #52）。
///
/// Moost が `claude` を子プロセスとして起動する際、Moost 自身のプロセスが
/// これらの変数を（Claude Code のターミナルセッションから開かれた等の経路で）
/// 保持していると fork/exec でそのまま子へ継承されてしまう。Claude Code は
/// `CLAUDE_CODE_CHILD_SESSION=1` 等を見ると「自分は子セッションだ」と誤認識し、
/// transcript の保存を止める。`CLAUDE_` プレフィックスによる判定を主とし、
/// パターンに乗らない既知の変数だけを個別リストで補う。
/// リファレンス実装: packages/core/lib/src/claude_code_environment.dart。
public enum ClaudeEnvironment {
    /// プレフィックスにマッチしない、既知の Claude Code 関連変数。
    static let nonPrefixedEnvVars: Set<String> = ["CLAUDECODE", "AI_AGENT"]

    /// これまでに実際に観測された Claude Code 内部環境変数名（決め打ちリスト）。
    /// AppleScript 経由でターミナルへコマンド文字列として渡す経路では
    /// 動的なプレフィックスマッチを埋め込めないため、この決め打ちリストを
    /// `env -u` プレフィックスで使う（新しい変数が見つかったら追加する）。
    public static let knownEnvVarNames: [String] = [
        "CLAUDECODE",
        "CLAUDE_CODE_ENTRYPOINT",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_ENABLE_TELEMETRY",
        "CLAUDE_EFFORT",
        "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE",
        "CLAUDE_CODE_EXECPATH",
        "CLAUDE_PID",
        "AI_AGENT",
    ]

    /// [key] が Claude Code 関連の内部環境変数とみなせるか。
    public static func isInternalEnvVar(_ key: String) -> Bool {
        if nonPrefixedEnvVars.contains(key) { return true }
        return key.hasPrefix("CLAUDE_")
    }

    /// [env] から Claude Code 関連の内部環境変数だけを取り除いた辞書を返す。
    /// `Process.environment` にそのまま渡せる。
    public static func withoutInternalEnv(_ env: [String: String]) -> [String: String] {
        env.filter { !isInternalEnvVar($0.key) }
    }

    /// `env -u VAR1 -u VAR2 ... ` の形のシェルコマンドプレフィックス。
    /// 環境が汚染されているかどうかを問わず常に付けてよい。
    public static func unsetPrefix() -> String {
        "env " + knownEnvVarNames.map { "-u \($0)" }.joined(separator: " ") + " "
    }
}
