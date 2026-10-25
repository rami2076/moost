using System.Globalization;

namespace Moost.Core;

/// <summary>
/// UTC ISO8601（<c>2026-09-20T09:00:00.000Z</c>）の書式（B6）。
/// リファレンス実装の <c>toUtc().toIso8601String()</c> と相互運用できる形にする。
/// </summary>
public static class IsoUtc
{
    /// <summary>書き込み側の書式（ミリ秒 3 桁 + Z）。</summary>
    public const string FormatString = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'";

    /// <summary>UTC の ISO8601 文字列に整形する。</summary>
    public static string Format(DateTime value) =>
        value.ToUniversalTime().ToString(FormatString, CultureInfo.InvariantCulture);

    /// <summary>
    /// 読み取り側は寛容にする（B6）: ミリ秒の有無、オフセット表記、秒精度まで受理する。
    /// パースできなければ false。
    /// </summary>
    public static bool TryParse(string? text, out DateTime value)
    {
        value = default;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (!DateTimeOffset.TryParse(
                text,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed))
        {
            return false;
        }

        value = parsed.UtcDateTime;
        return true;
    }
}
