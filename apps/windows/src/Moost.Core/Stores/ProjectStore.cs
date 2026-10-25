using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// 登録プロジェクトの CRUD（conformance D1・D2）。リファレンス実装: <c>store/project_store.dart</c>。
///
/// エンベロープ形式は <c>{"schemaVersion": 1, "projects": [...]}</c>（D1）。
/// 登録プロジェクトは編集できるフィールドを持たないため update はない（requirements.md 3.8）。
/// </summary>
public sealed class ProjectStore
{
    private readonly JsonFileStore _store;

    public ProjectStore(string filePath)
    {
        _store = new JsonFileStore(filePath);
    }

    /// <summary>読み書き対象の絶対パス。</summary>
    public string FilePath => _store.FilePath;

    /// <summary>既定の保存先（<c>%USERPROFILE%\.moost\v2\projects.json</c>）を使う。</summary>
    public static ProjectStore DefaultLocation() => new(DataDirectory.ProjectsFile());

    /// <summary>全件読み込む。壊れた 1 件はスキップする（ストア全体を捨てない）。</summary>
    /// <exception cref="IOException">読み取り自体に失敗した場合（A3）。</exception>
    public IReadOnlyList<Project> Load()
    {
        var json = _store.Read();
        if (json is null)
        {
            return [];
        }

        if (JsonRead.Array(json, "projects") is not { } rawProjects)
        {
            return [];
        }

        var projects = new List<Project>(rawProjects.Count);
        foreach (var node in rawProjects)
        {
            if (node is JsonObject item && Project.TryFromJson(item, out var project))
            {
                projects.Add(project);
            }
        }

        return projects;
    }

    public void Add(Project project)
    {
        var projects = Load().ToList();
        projects.Add(project);
        Save(projects);
    }

    public bool Delete(string id)
    {
        var projects = Load().ToList();
        var removed = projects.RemoveAll(project => project.Id == id);
        if (removed == 0)
        {
            return false;
        }

        Save(projects);
        return true;
    }

    /// <summary>一覧をまとめて保存する（並び替えなどで使う）。</summary>
    public void Save(IReadOnlyList<Project> projects) =>
        _store.Write(new JsonObject
        {
            ["schemaVersion"] = DataDirectory.SchemaVersion,
            ["projects"] = new JsonArray(projects.Select(project => (JsonNode?)project.ToJson()).ToArray()),
        });
}
