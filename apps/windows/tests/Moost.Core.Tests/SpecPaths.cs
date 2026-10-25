namespace Moost.Core.Tests;

/// <summary>
/// <c>spec/</c>（製品契約の正本）を解決する。
///
/// テストは Fixture をコピーせず、リポジトリ直下の <c>spec/</c> をそのまま読む。
/// こうすることで、macOS / Windows / Dart の各実装が**同一の Fixture** で検証される
/// （native-migration-plan.md 7.1）。コピーを作ると実装ごとにズレが生まれる。
/// </summary>
public static class SpecPaths
{
    /// <summary>spec ディレクトリの絶対パス。</summary>
    public static string Root { get; } = Locate();

    /// <summary>適合検証の項目一覧（spec/conformance.md）。</summary>
    public static string Conformance => Path.Combine(Root, "conformance.md");

    /// <summary>JSON Schema（spec/schemas/&lt;name&gt;）。</summary>
    public static string Schema(string name) => Path.Combine(Root, "schemas", name);

    /// <summary>共通 Fixture（spec/testdata/&lt;relativePath&gt;）。</summary>
    public static string TestData(string relativePath) =>
        Path.Combine(Root, "testdata", relativePath);

    private static string Locate()
    {
        // bin/<Configuration>/<TargetFramework>/ から親へ遡り、spec/conformance.md を持つ
        // ディレクトリをリポジトリルートとみなす（作業ディレクトリに依存しない）。
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "spec");
            if (File.Exists(Path.Combine(candidate, "conformance.md")))
            {
                return candidate;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "spec/ が見つかりません。リポジトリのチェックアウト内でテストを実行してください。");
    }
}
