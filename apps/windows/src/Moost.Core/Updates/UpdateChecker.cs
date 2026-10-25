using System.Globalization;
using System.Net;
using System.Net.Http;

namespace Moost.Core;

/// <summary>新しいバージョンが見つかったときの情報。</summary>
public sealed record UpdateInfo
{
    /// <summary>タグ（例: <c>v1.0.3-windows</c>）。</summary>
    public required string Tag { get; init; }

    /// <summary>プラットフォーム接尾辞を除いたバージョン（例: <c>1.0.3</c>）。</summary>
    public required string Semver { get; init; }

    /// <summary>リリースページの URL。</summary>
    public required string Url { get; init; }
}

/// <summary>
/// 更新チェック（docs/app-update-check-methods.md **方式 7 = リダイレクト方式**・#108）。
///
/// <list type="bullet">
/// <item><c>HEAD https://github.com/rami2076/moost/releases/latest</c> の 302 <c>Location</c> からタグを読む</item>
/// <item>GitHub Releases API はレート制限があるため使わない（方式 7 なら制限の概念がない）</item>
/// <item><b>Windows 系列のタグ（<c>v*-windows</c>）だけ</b>を比較する（macOS の v2.x に反応しない）</item>
/// <item>失敗しても沈黙する（例外を投げず null を返す）</item>
/// <item>実行は 5 分間隔に間引く（起動時＋ポップオーバー表示時に呼ばれるため）</item>
/// </list>
/// </summary>
public sealed class UpdateChecker
{
    /// <summary>リダイレクト先を読むための URL（方式 7）。</summary>
    public const string LatestReleaseUrl = "https://github.com/rami2076/moost/releases/latest";

    /// <summary>既定の再チェック間隔。</summary>
    public static readonly TimeSpan DefaultInterval = TimeSpan.FromMinutes(5);

    private readonly HttpClient _http;
    private readonly string _currentVersion;
    private readonly Func<DateTime> _now;
    private readonly TimeSpan _interval;

    private DateTime? _lastCheckedAt;
    private UpdateInfo? _lastResult;

    public UpdateChecker(
        string currentVersion,
        HttpClient? http = null,
        Func<DateTime>? now = null,
        TimeSpan? interval = null)
    {
        _currentVersion = currentVersion;
        _http = http ?? CreateHttpClient();
        _now = now ?? (() => DateTime.UtcNow);
        _interval = interval ?? DefaultInterval;
    }

    /// <summary>最後に取得した結果（未チェック・失敗時は null）。</summary>
    public UpdateInfo? LastResult => _lastResult;

    /// <summary>
    /// 新しいバージョンがあれば返す。無い・失敗・間隔内なら null（沈黙）。
    /// </summary>
    public async Task<UpdateInfo?> CheckAsync(CancellationToken cancellationToken = default)
    {
        var now = _now();
        if (_lastCheckedAt is { } last && now - last < _interval)
        {
            // 間隔内はネットワークに出ない（前回の結果をそのまま返す）
            return _lastResult;
        }

        _lastCheckedAt = now;
        _lastResult = null;

        try
        {
            var tag = await FetchLatestTagAsync(cancellationToken).ConfigureAwait(false);
            if (tag is null || !TryParseWindowsTag(tag, out var semver))
            {
                return null;
            }

            if (CompareSemver(semver, _currentVersion) <= 0)
            {
                return null;
            }

            _lastResult = new UpdateInfo
            {
                Tag = tag,
                Semver = semver,
                Url = $"https://github.com/rami2076/moost/releases/tag/{tag}",
            };
            return _lastResult;
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException or OperationCanceledException)
        {
            // 失敗しても沈黙する（ユーザーに通知も例外も出さない）
            return null;
        }
    }

    /// <summary>302 の Location からタグを取り出す（取れなければ null）。</summary>
    private async Task<string?> FetchLatestTagAsync(CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Head, LatestReleaseUrl);
        request.Headers.TryAddWithoutValidation("User-Agent", "Moost/" + _currentVersion);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));

        using var response = await _http
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token)
            .ConfigureAwait(false);

        if (response.StatusCode is not (HttpStatusCode.Found or HttpStatusCode.MovedPermanently or HttpStatusCode.TemporaryRedirect))
        {
            return null;
        }

        var location = response.Headers.Location;
        if (location is null)
        {
            return null;
        }

        // Location: https://github.com/rami2076/moost/releases/tag/v1.0.3-windows
        var segments = location.ToString().TrimEnd('/').Split('/');
        var tag = segments[^1];
        return tag.StartsWith('v') ? tag : null;
    }

    /// <summary><c>v1.0.3-windows</c> → <c>1.0.3</c>。Windows 系列でなければ false。</summary>
    public static bool TryParseWindowsTag(string tag, out string semver)
    {
        semver = string.Empty;
        if (!tag.StartsWith('v'))
        {
            return false;
        }

        var body = tag[1..];
        var dash = body.LastIndexOf('-');
        if (dash <= 0)
        {
            return false;
        }

        var platform = body[(dash + 1)..];
        if (!platform.Equals("windows", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var candidate = body[..dash];
        if (!IsSemver(candidate))
        {
            return false;
        }

        semver = candidate;
        return true;
    }

    /// <summary>数値 3 要素の semver を比較する（<paramref name="left"/> &gt; <paramref name="right"/> なら正）。</summary>
    public static int CompareSemver(string left, string right)
    {
        var a = ParseParts(left);
        var b = ParseParts(right);
        for (var index = 0; index < 3; index++)
        {
            var result = a[index].CompareTo(b[index]);
            if (result != 0)
            {
                return result;
            }
        }

        return 0;
    }

    private static int[] ParseParts(string version)
    {
        var parts = version.Split('.');
        var numbers = new int[3];
        for (var index = 0; index < 3; index++)
        {
            numbers[index] = index < parts.Length
                && int.TryParse(parts[index], NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
                ? value
                : 0;
        }

        return numbers;
    }

    private static bool IsSemver(string value)
    {
        // 3 要素（MAJOR.MINOR.PATCH）だけを semver として扱う
        var parts = value.Split('.');
        return parts.Length == 3
            && parts.All(part => part.Length > 0 && part.All(char.IsAsciiDigit));
    }

    private static HttpClient CreateHttpClient()
    {
        // 302 を自動追跡しない（Location ヘッダからタグを読むため）
        var handler = new HttpClientHandler { AllowAutoRedirect = false };
        return new HttpClient(handler, disposeHandler: true);
    }
}

/// <summary>
/// 導入方法の判定と更新コマンド（#108）。
///
/// winget 管理下（<c>...\Microsoft\WinGet\Packages\...</c> から起動）なら
/// <c>winget upgrade</c> を案内し、そうでなければリリースページを開く。
/// Scoop は不採用（#109）なので分岐は 2 つだけ。
/// </summary>
public static class UpdateGuidance
{
    public const string WingetUpgradeCommand = "winget upgrade --id rami2076.Moost -e";

    /// <summary>winget の管理下に置かれた exe か。</summary>
    public static bool IsWingetManaged(string? processPath) =>
        processPath is not null
        && processPath.Contains(@"\Microsoft\WinGet\Packages\", StringComparison.OrdinalIgnoreCase);

    /// <summary>更新導線として提示するコマンド（winget 管理下でなければ null＝リリースページを開く）。</summary>
    public static string? CommandFor(string? processPath) =>
        IsWingetManaged(processPath) ? WingetUpgradeCommand : null;
}
