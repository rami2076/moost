namespace Moost.Core;

/// <summary>
/// Moost のデータ配置（Windows）。
///
/// 保存先は <c>%USERPROFILE%\.moost\v2\</c>（macOS の <c>~/.moost/v2/</c> に対応）。
/// Windows には旧世代（v1 = Flutter 版）のデータが存在しないため、
/// v1 → v2 の移行処置は行わない（native-migration-plan.md 6 章の注記）。
/// </summary>
public static class DataDirectory
{
    /// <summary>データ契約の版番号（アプリ/プラの版番号とは独立）。</summary>
    public const int SchemaVersion = 1;

    public const string FolderName = ".moost";
    public const string Generation = "v2";

    /// <summary>データディレクトリの絶対パスを返す（作成はしない）。</summary>
    /// <param name="userProfile">テスト用の上書き。null なら OS のユーザープロファイル。</param>
    public static string Resolve(string? userProfile = null)
    {
        var profile = userProfile ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(profile, FolderName, Generation);
    }

    public static string MemosFile(string? userProfile = null) =>
        Path.Combine(Resolve(userProfile), "memos.json");

    public static string SettingsFile(string? userProfile = null) =>
        Path.Combine(Resolve(userProfile), "settings.json");

    public static string ProjectsFile(string? userProfile = null) =>
        Path.Combine(Resolve(userProfile), "projects.json");
}
