using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// <c>%USERPROFILE%\.moost\v2\settings.json</c> の読み書き（conformance C1〜C4）。
/// リファレンス実装: <c>store/settings_store.dart</c>。
///
/// 読み込みは寛容: 型が想定と違う項目は <b>その項目だけ</b>デフォルトへフォールバックする
/// （ファイル全体を捨てない・C1）。
/// </summary>
public sealed class SettingsStore
{
    private readonly JsonFileStore _store;

    public SettingsStore(string filePath)
    {
        _store = new JsonFileStore(filePath);
    }

    /// <summary>読み書き対象の絶対パス。</summary>
    public string FilePath => _store.FilePath;

    /// <summary>既定の保存先（<c>%USERPROFILE%\.moost\v2\settings.json</c>）を使う。</summary>
    public static SettingsStore DefaultLocation() => new(DataDirectory.SettingsFile());

    /// <summary>
    /// 設定を読み込む。ファイル不在なら既定値（C2）。壊れた JSON は退避して既定値（A2）。
    /// </summary>
    /// <exception cref="IOException">読み取り自体に失敗した場合（A3）。</exception>
    public Settings Load()
    {
        var json = _store.Read();
        if (json is null)
        {
            return Settings.Default;
        }

        // 項目ごとに型を確かめ、違えばその項目だけデフォルトに戻す（C1）
        return new Settings
        {
            TerminalApp = JsonRead.TryString(json, "terminalApp", out var terminalApp)
                ? terminalApp
                : Settings.Default.TerminalApp,
            RecentSessionLimit = JsonRead.TryInt(json, "recentSessionLimit", out var recentSessionLimit)
                ? recentSessionLimit
                : Settings.Default.RecentSessionLimit,
            ClaudePath = JsonRead.TryString(json, "claudePath", out var claudePath)
                ? claudePath
                : Settings.Default.ClaudePath,
            SummaryRallyCount = JsonRead.TryInt(json, "summaryRallyCount", out var summaryRallyCount)
                ? summaryRallyCount
                : Settings.Default.SummaryRallyCount,
            CopyAnimation = JsonRead.TryBool(json, "copyAnimation", out var copyAnimation)
                ? copyAnimation
                : Settings.Default.CopyAnimation,
            PiProvider = JsonRead.TryString(json, "piProvider", out var piProvider)
                ? piProvider
                : Settings.Default.PiProvider,
            PiModel = JsonRead.TryString(json, "piModel", out var piModel)
                ? piModel
                : Settings.Default.PiModel,
        };
    }

    /// <summary>
    /// 設定を保存する。ログイン時自動起動は<b>保存しない</b>（C4）。
    /// </summary>
    public void Save(Settings settings) =>
        _store.Write(new JsonObject
        {
            ["schemaVersion"] = DataDirectory.SchemaVersion,
            ["terminalApp"] = settings.TerminalApp,
            ["recentSessionLimit"] = settings.RecentSessionLimit,
            ["claudePath"] = settings.ClaudePath,
            ["summaryRallyCount"] = settings.SummaryRallyCount,
            ["copyAnimation"] = settings.CopyAnimation,
            ["piProvider"] = settings.PiProvider,
            ["piModel"] = settings.PiModel,
        });
}
