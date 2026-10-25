using System.Windows.Media;

namespace Moost.WindowsApp.Views;

/// <summary>
/// エージェントの表示名とバッジ色（macOS の <c>AppRootView</c> の <c>color(for:)</c> と同値）。
/// </summary>
public static class AgentVisual
{
    /// <summary>表示名（claude-code → Claude など）。</summary>
    public static string DisplayName(string agentId) => agentId switch
    {
        "claude-code" => "Claude",
        "codex" => "Codex",
        "pi" => "pi",
        "hermes" => "Hermes",
        _ => agentId,
    };

    /// <summary>プロジェクト行のエージェントボタン用の短い記号。</summary>
    public static string ShortLabel(string agentId) => agentId switch
    {
        "claude-code" => "C",
        "codex" => "X",
        "pi" => "P",
        "hermes" => "H",
        _ => "?",
    };

    /// <summary>バッジ色（macOS と同じ値）。</summary>
    public static Brush Color(string agentId) => agentId switch
    {
        "claude-code" => Brush("#D97757"),
        "codex" => Brush("#6867AA"),
        "pi" => Brush("#2E7D9E"),
        "hermes" => Brush("#8E44AD"),
        _ => Brush("#8A8A8A"),
    };

    private static Brush Brush(string hex)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        brush.Freeze();
        return brush;
    }
}

/// <summary>画面遷移（単一画面のステートマシン・design.md 6.1）。</summary>
public interface IAppNavigator
{
    void ShowList();

    void ShowMemoForm(Moost.Core.RecentSession? session, Moost.Core.Memo? memo);

    void ShowDetail(Moost.Core.RecentSession session);

    void ShowSettings();

    void ShowNotes();
}
