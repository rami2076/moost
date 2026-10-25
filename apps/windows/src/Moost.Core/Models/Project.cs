using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// ユーザーが新規セッション起動のために明示的に登録したディレクトリ（conformance D 章）。
/// リファレンス実装: <c>packages/core/lib/src/model/project.dart</c>。
///
/// メモと異なりセッションに紐づかず、<c>agent</c> も持たない。セッションが 1 件もない
/// ディレクトリでも登録できる（CONTEXT.md「登録プロジェクト」、ADR-004）。
/// </summary>
public sealed record Project
{
    public required string Id { get; init; }

    public required string ProjectPath { get; init; }

    public required DateTime CreatedAt { get; init; }

    /// <summary>
    /// 一覧表示用の名前。<see cref="ProjectPath"/> の最後のディレクトリ名を都度導出する
    /// （保存はしない・D2）。
    /// </summary>
    public string DisplayName => DeriveDisplayName(ProjectPath);

    /// <summary>
    /// パスの末尾区切りを除いた最後のセグメントを返す（D2）。
    /// 抽出できない場合は <paramref name="projectPath"/> をそのまま返す。
    ///
    /// Windows 実装では区切りを <c>/</c> と <c>\</c> の両方で扱う
    /// （リファレンス実装は POSIX 前提で <c>/</c> のみ。データ契約の期待値は
    /// 「最後のディレクトリ名」であり、区切りの種類には依存しない）。
    /// </summary>
    public static string DeriveDisplayName(string projectPath)
    {
        if (string.IsNullOrEmpty(projectPath))
        {
            return projectPath;
        }

        var trimmed = projectPath.TrimEnd('/', '\\');
        if (trimmed.Length == 0)
        {
            // ルート（"/" や "\\"）だけの場合は抽出不能として元のパスを返す
            return projectPath;
        }

        var separator = trimmed.LastIndexOfAny(['/', '\\']);
        var segment = separator >= 0 ? trimmed[(separator + 1)..] : trimmed;
        return segment.Length == 0 ? projectPath : segment;
    }

    public JsonObject ToJson() => new()
    {
        ["id"] = Id,
        ["projectPath"] = ProjectPath,
        ["createdAt"] = IsoUtc.Format(CreatedAt),
    };

    public static bool TryFromJson(JsonObject json, out Project project)
    {
        project = null!;

        if (!JsonRead.TryString(json, "id", out var id)
            || !JsonRead.TryString(json, "projectPath", out var projectPath)
            || !JsonRead.TryString(json, "createdAt", out var createdAtText)
            || !IsoUtc.TryParse(createdAtText, out var createdAt))
        {
            return false;
        }

        project = new Project { Id = id, ProjectPath = projectPath, CreatedAt = createdAt };
        return true;
    }
}
