namespace Moost.Core.Tests;

/// <summary>
/// テスト用の一時ディレクトリ。書き込みを伴うテストは <c>spec/</c> を直接触らず、
/// ここへ Fixture をコピーしてから使う（spec は読み取り専用の正本として保つ）。
/// </summary>
internal sealed class TempDir : IDisposable
{
    public string Path { get; }

    public TempDir()
    {
        Path = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "moost-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    /// <summary>一時ディレクトリ内のファイルパス。</summary>
    public string File(string name) => System.IO.Path.Combine(Path, name);

    /// <summary><c>spec/testdata/&lt;relativePath&gt;</c> をコピーして、そのパスを返す。</summary>
    public string CopyFixture(string relativePath, string? name = null)
    {
        var target = File(name ?? System.IO.Path.GetFileName(relativePath));
        System.IO.File.Copy(SpecPaths.TestData(relativePath), target, overwrite: true);
        return target;
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
            // 一時ディレクトリの掃除失敗はテスト結果に影響させない
        }
    }
}
