using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// メモの CRUD（conformance B1〜B4）。リファレンス実装: <c>store/memo_store.dart</c>。
///
/// エンベロープ形式は <c>{"schemaVersion": 1, "memos": [...]}</c>（B1）。
/// update で変更できるのは title / tags / body（+ updatedAt）のみ（ADR-003）。
/// </summary>
public sealed class MemoStore
{
    private readonly JsonFileStore _store;

    public MemoStore(string filePath)
    {
        _store = new JsonFileStore(filePath);
    }

    /// <summary>読み書き対象の絶対パス。</summary>
    public string FilePath => _store.FilePath;

    /// <summary>既定の保存先（<c>%USERPROFILE%\.moost\v2\memos.json</c>）を使う。</summary>
    public static MemoStore DefaultLocation() => new(DataDirectory.MemosFile());

    /// <summary>
    /// 全件読み込む。壊れた 1 件はスキップし、ストア全体を捨てない（B3）。
    /// </summary>
    /// <exception cref="IOException">読み取り自体に失敗した場合（A3）。</exception>
    public IReadOnlyList<Memo> Load()
    {
        var json = _store.Read();
        if (json is null)
        {
            return [];
        }

        if (JsonRead.Array(json, "memos") is not { } rawMemos)
        {
            return [];
        }

        var memos = new List<Memo>(rawMemos.Count);
        foreach (var node in rawMemos)
        {
            if (node is JsonObject item && Memo.TryFromJson(item, out var memo))
            {
                memos.Add(memo);
            }
        }

        return memos;
    }

    public void Add(Memo memo)
    {
        var memos = Load().ToList();
        memos.Add(memo);
        Save(memos);
    }

    /// <summary>
    /// 可変フィールドだけを更新する。対象が見つからなければ false（B4）。
    /// </summary>
    public bool Update(
        string id,
        string? title = null,
        IReadOnlyList<string>? tags = null,
        string? body = null,
        DateTime? updatedAt = null)
    {
        var memos = Load().ToList();
        var index = memos.FindIndex(memo => memo.Id == id);
        if (index < 0)
        {
            return false;
        }

        memos[index] = memos[index].UpdateUserFields(title, tags, body, updatedAt ?? DateTime.UtcNow);
        Save(memos);
        return true;
    }

    public bool Delete(string id)
    {
        var memos = Load().ToList();
        var removed = memos.RemoveAll(memo => memo.Id == id);
        if (removed == 0)
        {
            return false;
        }

        Save(memos);
        return true;
    }

    private void Save(IReadOnlyList<Memo> memos) =>
        _store.Write(new JsonObject
        {
            ["schemaVersion"] = DataDirectory.SchemaVersion,
            ["memos"] = new JsonArray(memos.Select(memo => (JsonNode?)memo.ToJson()).ToArray()),
        });
}
