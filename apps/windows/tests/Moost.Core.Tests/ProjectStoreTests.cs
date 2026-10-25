using System.Text.Json.Nodes;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance D 章（projects.json）。
/// </summary>
public class ProjectStoreTests
{
    private static Project NewProject(string path) => new()
    {
        Id = Guid.NewGuid().ToString(),
        ProjectPath = path,
        CreatedAt = new DateTime(2026, 9, 20, 9, 0, 0, DateTimeKind.Utc),
    };

    [Fact]
    public void D1_Envelope_HasSchemaVersionAndProjects()
    {
        using var dir = new TempDir();
        var path = dir.File("projects.json");
        var store = new ProjectStore(path);

        store.Add(NewProject("/work/auth-service"));

        var json = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        Assert.Equal(1, json["schemaVersion"]!.GetValue<int>());

        var project = Assert.Single(json["projects"]!.AsArray());
        Assert.Equal("/work/auth-service", project!["projectPath"]!.GetValue<string>());
        Assert.False(project["id"] is null);
        Assert.False(project["createdAt"] is null);
    }

    [Fact]
    public void D1_AddAndDelete_RoundTrip()
    {
        using var dir = new TempDir();
        var store = new ProjectStore(dir.File("projects.json"));
        var project = NewProject("/work/p1");

        store.Add(project);
        Assert.Single(store.Load());

        Assert.True(store.Delete(project.Id));
        Assert.Empty(store.Load());
        Assert.False(store.Delete(project.Id));
    }

    [Theory]
    [InlineData("/work/auth-service", "auth-service")]
    [InlineData("/work/auth-service/", "auth-service")]
    [InlineData(@"C:\Users\me\proj", "proj")]
    [InlineData(@"C:\Users\me\proj\", "proj")]
    [InlineData(@"C:/Users/me/proj/", "proj")]
    [InlineData("single", "single")]
    [InlineData("/", "/")]
    [InlineData("", "")]
    public void D2_DisplayName_IsDerivedFromProjectPath(string projectPath, string expected)
    {
        Assert.Equal(expected, Project.DeriveDisplayName(projectPath));
        Assert.Equal(expected, NewProject(projectPath).DisplayName);
    }

    [Fact]
    public void D2_DisplayName_IsNotPersisted()
    {
        using var dir = new TempDir();
        var path = dir.File("projects.json");
        new ProjectStore(path).Add(NewProject("/work/auth-service"));

        var json = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var project = json["projects"]!.AsArray()[0]!.AsObject();

        Assert.DoesNotContain("displayName", project.Select(pair => pair.Key));
    }

    [Fact]
    public void CorruptEntry_IsSkipped_StoreIsNotDiscarded()
    {
        using var dir = new TempDir();
        var path = dir.File("projects.json");
        File.WriteAllText(path, """
            {
              "schemaVersion": 1,
              "projects": [
                { "id": "ok", "projectPath": "/work/ok", "createdAt": "2026-09-01T00:00:00.000Z" },
                { "id": "bad", "projectPath": 42, "createdAt": "not-a-date" }
              ]
            }
            """);

        var project = Assert.Single(new ProjectStore(path).Load());
        Assert.Equal("ok", project.Id);
    }

    [Fact]
    public void Load_OnMissingFile_ReturnsEmpty()
    {
        using var dir = new TempDir();
        Assert.Empty(new ProjectStore(dir.File("projects.json")).Load());
    }

    [Fact]
    public void DefaultLocation_UsesUserProfileMoostV2()
    {
        var profile = System.IO.Path.Combine("C:", "Users", "someone");
        Assert.Equal(
            System.IO.Path.Combine(profile, ".moost", "v2", "projects.json"),
            DataDirectory.ProjectsFile(profile));
        Assert.Equal(
            System.IO.Path.Combine(profile, ".moost", "v2", "memos.json"),
            DataDirectory.MemosFile(profile));
        Assert.Equal(
            System.IO.Path.Combine(profile, ".moost", "v2", "settings.json"),
            DataDirectory.SettingsFile(profile));
    }
}
