import XCTest
@testable import MoostCore

/// Claude Code 内部環境変数のフィルタ（Issue #52）。
/// リファレンス: claude_code_environment_test.dart。
final class ClaudeEnvironmentTests: XCTestCase {
    func test_is_internal_env_var_matches_known_non_prefixed() {
        XCTAssertTrue(ClaudeEnvironment.isInternalEnvVar("CLAUDECODE"))
        XCTAssertTrue(ClaudeEnvironment.isInternalEnvVar("AI_AGENT"))
    }

    func test_is_internal_env_var_matches_any_claude_prefixed_var() {
        // CLAUDE_PID は事前の固定リストになかった実例。プレフィックスマッチなら
        // 個別追加なしで拾えることを確認する
        XCTAssertTrue(ClaudeEnvironment.isInternalEnvVar("CLAUDE_PID"))
        XCTAssertTrue(ClaudeEnvironment.isInternalEnvVar("CLAUDE_CODE_CHILD_SESSION"))
        XCTAssertTrue(ClaudeEnvironment.isInternalEnvVar("CLAUDE_SOME_FUTURE_VAR"))
    }

    func test_is_internal_env_var_does_not_match_unrelated() {
        XCTAssertFalse(ClaudeEnvironment.isInternalEnvVar("PATH"))
        XCTAssertFalse(ClaudeEnvironment.isInternalEnvVar("HOME"))
        XCTAssertFalse(ClaudeEnvironment.isInternalEnvVar("ANTHROPIC_API_KEY"))
    }

    func test_without_internal_env_removes_internal_keeps_others() {
        let filtered = ClaudeEnvironment.withoutInternalEnv([
            "PATH": "/usr/bin",
            "HOME": "/Users/x",
            "CLAUDE_CODE_CHILD_SESSION": "1",
            "CLAUDE_PID": "123",
            "AI_AGENT": "claude-code",
            "CLAUDECODE": "1",
        ])
        XCTAssertEqual(filtered, ["PATH": "/usr/bin", "HOME": "/Users/x"])
    }

    func test_unset_prefix_covers_every_known_var() {
        let prefix = ClaudeEnvironment.unsetPrefix()
        XCTAssertTrue(prefix.hasPrefix("env "))
        XCTAssertTrue(prefix.hasSuffix(" "))
        for name in ClaudeEnvironment.knownEnvVarNames {
            XCTAssertTrue(prefix.contains("-u \(name)"))
        }
    }
}

/// 要約結果のメモリキャッシュ。
/// リファレンス: summary_cache_test.dart。
final class SummaryCacheTests: XCTestCase {
    func test_returns_nil_on_miss() {
        let cache = SummaryCache()
        XCTAssertNil(cache.get("s1", scope: .full, rallies: 1))
    }

    func test_stores_and_retrieves_by_session_and_scope() {
        let cache = SummaryCache()
        cache.put("s1", scope: .full, rallies: 1, summary: "full summary")
        cache.put("s1", scope: .recent, rallies: 3, summary: "recent-3 summary")
        XCTAssertEqual(cache.get("s1", scope: .full, rallies: 1), "full summary")
        XCTAssertEqual(cache.get("s1", scope: .recent, rallies: 3), "recent-3 summary")
    }

    func test_rally_count_is_part_of_key_for_recent_scope() {
        let cache = SummaryCache()
        cache.put("s1", scope: .recent, rallies: 1, summary: "one")
        XCTAssertEqual(cache.get("s1", scope: .recent, rallies: 1), "one")
        XCTAssertNil(cache.get("s1", scope: .recent, rallies: 5))
    }

    func test_rally_count_ignored_for_full_scope() {
        let cache = SummaryCache()
        cache.put("s1", scope: .full, rallies: 1, summary: "full")
        XCTAssertEqual(cache.get("s1", scope: .full, rallies: 99), "full")
    }

    func test_sessions_are_isolated() {
        let cache = SummaryCache()
        cache.put("s1", scope: .full, rallies: 1, summary: "a")
        XCTAssertNil(cache.get("s2", scope: .full, rallies: 1))
    }

    func test_clear_empties_cache() {
        let cache = SummaryCache()
        cache.put("s1", scope: .full, rallies: 1, summary: "a")
        cache.clear()
        XCTAssertNil(cache.get("s1", scope: .full, rallies: 1))
    }
}
