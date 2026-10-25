using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// 人がセッションに付ける記録（conformance B 章）。
/// リファレンス実装: <c>packages/core/lib/src/model/memo.dart</c>。
///
/// 復帰に必要な情報（<see cref="SessionId"/> + <see cref="ProjectPath"/>）を自己完結で持つため、
/// エージェント側の履歴から元セッションが消えた後でもメモからの復帰が機能する。
/// 編集で変更できるのは <see cref="Title"/> / <see cref="Tags"/> / <see cref="Body"/> のみ（ADR-003）。
/// </summary>
public sealed record Memo
{
    public required string Id { get; init; }

    /// <summary>エージェント識別子（claude-code / codex / pi / hermes）。</summary>
    public required string Agent { get; init; }

    /// <summary>復帰対象セッション。不変。</summary>
    public required string SessionId { get; init; }

    /// <summary>可変フィールド。</summary>
    public required string Title { get; init; }

    /// <summary>可変。カンマ区切り入力を <see cref="ParseTags"/> で正規化して保存する。</summary>
    public required IReadOnlyList<string> Tags { get; init; }

    /// <summary>可変フィールド。</summary>
    public required string Body { get; init; }

    /// <summary>不変。復帰コマンドの cd 先。</summary>
    public required string ProjectPath { get; init; }

    public required DateTime CreatedAt { get; init; }

    public required DateTime UpdatedAt { get; init; }

    /// <summary>
    /// 可変フィールド（title / tags / body）だけを差し替えたコピーを返す（B4）。
    /// <see cref="UpdatedAt"/> は必ず更新される（ADR-003）。
    /// </summary>
    public Memo UpdateUserFields(
        string? title = null,
        IReadOnlyList<string>? tags = null,
        string? body = null,
        DateTime? updatedAt = null) =>
        this with
        {
            Title = title ?? Title,
            Tags = tags ?? Tags,
            Body = body ?? Body,
            UpdatedAt = updatedAt ?? DateTime.UtcNow,
        };

    public JsonObject ToJson() => new()
    {
        ["id"] = Id,
        ["agent"] = Agent,
        ["sessionId"] = SessionId,
        ["title"] = Title,
        ["tags"] = new JsonArray(Tags.Select(tag => (JsonNode?)JsonValue.Create(tag)).ToArray()),
        ["body"] = Body,
        ["projectPath"] = ProjectPath,
        ["createdAt"] = IsoUtc.Format(CreatedAt),
        ["updatedAt"] = IsoUtc.Format(UpdatedAt),
    };

    /// <summary>
    /// 厳密に読み取る。型・日付のいずれかが契約と違えば false を返し、
    /// 呼び出し側がその 1 件だけスキップできるようにする（B3）。
    /// </summary>
    public static bool TryFromJson(JsonObject json, out Memo memo)
    {
        memo = null!;

        if (!JsonRead.TryString(json, "id", out var id)
            || !JsonRead.TryString(json, "agent", out var agent)
            || !JsonRead.TryString(json, "sessionId", out var sessionId)
            || !JsonRead.TryString(json, "title", out var title)
            || !JsonRead.TryString(json, "body", out var body)
            || !JsonRead.TryString(json, "projectPath", out var projectPath)
            || !JsonRead.TryString(json, "createdAt", out var createdAtText)
            || !JsonRead.TryString(json, "updatedAt", out var updatedAtText))
        {
            return false;
        }

        // tags は「文字列の配列」であること（文字列や数値の配列は不健全）
        if (JsonRead.Array(json, "tags") is not { } rawTags)
        {
            return false;
        }

        var tags = new List<string>(rawTags.Count);
        foreach (var node in rawTags)
        {
            if (node is not JsonValue value || !value.TryGetValue<string>(out var tag) || tag is null)
            {
                return false;
            }

            tags.Add(tag);
        }

        if (!IsoUtc.TryParse(createdAtText, out var createdAt)
            || !IsoUtc.TryParse(updatedAtText, out var updatedAt))
        {
            return false;
        }

        memo = new Memo
        {
            Id = id,
            Agent = agent,
            SessionId = sessionId,
            Title = title,
            Tags = tags,
            Body = body,
            ProjectPath = projectPath,
            CreatedAt = createdAt,
            UpdatedAt = updatedAt,
        };
        return true;
    }

    /// <summary>
    /// カンマ区切りのタグ入力を分割・トリム・空要素除去して配列にする（B5）。
    /// <c>"a, b ,,c"</c> → <c>["a","b","c"]</c>。
    /// </summary>
    public static IReadOnlyList<string> ParseTags(string input) =>
        (input ?? string.Empty)
            .Split(',')
            .Select(tag => tag.Trim())
            .Where(tag => tag.Length > 0)
            .ToArray();
}
