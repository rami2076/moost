namespace Moost.Core;

/// <summary>
/// 要約実行が作る「要約用フォークセッション」を一覧から除外するためのマーカー。
///
/// リファレンス実装（<c>ClaudeSummarizer.marker</c> / <c>CodexSummarizer.marker</c>）と同値。
/// conformance の Fixture は <see cref="ConformanceMarker"/> を使う（spec が正）。
/// </summary>
public static class SummaryMarker
{
    /// <summary>実運用のマーカー（要約プロンプトの先頭に付く）。</summary>
    public const string Value = "[Moost要約]";

    /// <summary>conformance Fixture（<c>spec/testdata/history.jsonl</c> 等）が使うマーカー。</summary>
    public const string ConformanceMarker = "#MOOST-FORK#";
}
