namespace Moost.Core;

/// <summary>
/// アプリ設定（conformance C1〜C4）。リファレンス実装: <c>store/settings_store.dart</c>。
///
/// ログイン時の自動起動はここに持たない（OS 側の実状態を正とする・C4）。
/// Windows では <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c> の実状態を毎回読む。
/// </summary>
public sealed record Settings
{
    /// <summary>復帰先ターミナル。<b>ENUM にしない</b>（C3・Issue #41）。既知外の値もそのまま保持する。</summary>
    public string TerminalApp { get; init; } = "Terminal.app";

    public int RecentSessionLimit { get; init; } = 20;

    /// <summary>要約に使う CLI パスの上書き。空なら自動検出。</summary>
    public string ClaudePath { get; init; } = "";

    public int SummaryRallyCount { get; init; } = 1;

    public bool CopyAnimation { get; init; } = true;

    /// <summary>pi 起動時の provider（空ならフラグを付けない・Issue #68）。</summary>
    public string PiProvider { get; init; } = "";

    /// <summary>pi 起動時の model（空ならフラグを付けない・Issue #68）。</summary>
    public string PiModel { get; init; } = "";

    /// <summary>既定値の設定。</summary>
    public static Settings Default { get; } = new();
}
