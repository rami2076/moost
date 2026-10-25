using System.Reflection;

namespace Moost.WindowsApp;

/// <summary>
/// アプリのバージョン。CI がタグから <c>-p:Version=</c> で注入した値を表示する
/// （コードに版番号を書かない・RELEASE.md 1.2）。
/// </summary>
public static class AppInfo
{
    /// <summary>表示用のバージョン（<c>1.0.3</c>。ビルドメタデータの <c>+hash</c> は落とす）。</summary>
    public static string Version { get; } = Read();

    private static string Read()
    {
        var attribute = typeof(AppInfo).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
        var value = attribute?.InformationalVersion;
        if (string.IsNullOrWhiteSpace(value))
        {
            return "0.0.0";
        }

        var plus = value.IndexOf('+', StringComparison.Ordinal);
        return plus >= 0 ? value[..plus] : value;
    }
}
