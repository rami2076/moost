namespace Moost.Core;

/// <summary>セッション要約の対象範囲（requirements.md 3.6）。</summary>
public enum SummaryScope
{
    /// <summary>直近 N ラリーの抜粋を渡す（高速・低コスト）。</summary>
    Recent,

    /// <summary>セッション全体を対象にする（時間と利用枠を多く消費する）。</summary>
    Full,
}

/// <summary>
/// 要約実行の失敗。ユーザーに見せられるメッセージを持つ。
/// リファレンス実装: <c>summarize_exception.dart</c> / <c>SummarySupport.swift</c>。
/// </summary>
public sealed class SummarizeException : Exception
{
    public SummarizeException(string message)
        : base(message)
    {
    }

    public SummarizeException(string message, Exception inner)
        : base(message, inner)
    {
    }
}

/// <summary>
/// セッション要約のメモリキャッシュ（ADR-002・design.md 5 章）。
/// 要約は<b>永続化しない</b>。アプリ常駐中のみ保持し、同じセッション詳細を
/// 開き直したときに CLI を再実行しないためのもの（時間と利用料の節約）。
/// キーは セッションID × 要約範囲（scope + ラリー数）。
/// </summary>
public sealed class SummaryCache
{
    private readonly Dictionary<string, string> _entries = new(StringComparer.Ordinal);
    private readonly Lock _lock = new();

    public string? Get(string sessionId, SummaryScope scope, int rallies)
    {
        lock (_lock)
        {
            return _entries.GetValueOrDefault(Key(sessionId, scope, rallies));
        }
    }

    public void Put(string sessionId, SummaryScope scope, int rallies, string summary)
    {
        lock (_lock)
        {
            _entries[Key(sessionId, scope, rallies)] = summary;
        }
    }

    public void Clear()
    {
        lock (_lock)
        {
            _entries.Clear();
        }
    }

    public int Count
    {
        get
        {
            lock (_lock)
            {
                return _entries.Count;
            }
        }
    }

    private static string Key(string sessionId, SummaryScope scope, int rallies) =>
        scope == SummaryScope.Full ? sessionId + ":full" : sessionId + ":recent" + rallies;
}
