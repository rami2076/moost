using System.Text.Json.Nodes;

namespace Moost.Core;

/// <summary>
/// JSON からの型付き取り出し。型が違う項目は「無かった」として扱い、
/// 呼び出し側でデフォルトへフォールバックさせる（C1 の寛容性）。
/// </summary>
internal static class JsonRead
{
    public static bool TryString(JsonObject json, string key, out string value)
    {
        value = string.Empty;
        if (json[key] is JsonValue node && node.TryGetValue<string>(out var text) && text is not null)
        {
            value = text;
            return true;
        }

        return false;
    }

    public static bool TryInt(JsonObject json, string key, out int value)
    {
        value = 0;
        if (json[key] is JsonValue node
            && node.GetValueKind() == System.Text.Json.JsonValueKind.Number
            && node.TryGetValue<int>(out var number))
        {
            value = number;
            return true;
        }

        return false;
    }

    public static bool TryBool(JsonObject json, string key, out bool value)
    {
        value = false;
        if (json[key] is JsonValue node
            && node.GetValueKind() is System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False
            && node.TryGetValue<bool>(out var flag))
        {
            value = flag;
            return true;
        }

        return false;
    }

    public static JsonArray? Array(JsonObject json, string key) =>
        json[key] is JsonArray array ? array : null;
}
