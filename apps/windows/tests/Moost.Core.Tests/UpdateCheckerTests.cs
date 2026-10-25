using System.Net;
using System.Net.Http;
using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// 更新チェック（方式 7 = リダイレクト・#108）。HTTP は差し替えてネットワークに出ない。
/// </summary>
public class UpdateCheckerTests
{
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _responder;

        public StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) => _responder = responder;

        public int Calls { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(_responder(request));
        }
    }

    private static HttpResponseMessage Redirect(string tag) => new(HttpStatusCode.Found)
    {
        Headers = { Location = new Uri($"https://github.com/rami2076/moost/releases/tag/{tag}") },
    };

    private static UpdateChecker Create(string current, Func<HttpRequestMessage, HttpResponseMessage> responder, out StubHandler handler, Func<DateTime>? now = null)
    {
        handler = new StubHandler(responder);
        return new UpdateChecker(current, new HttpClient(handler), now);
    }

    [Fact]
    public async Task NewerWindowsTag_IsReported()
    {
        var checker = Create("1.0.2", _ => Redirect("v1.0.3-windows"), out var handler);

        var update = await checker.CheckAsync();

        Assert.NotNull(update);
        Assert.Equal("v1.0.3-windows", update!.Tag);
        Assert.Equal("1.0.3", update.Semver);
        Assert.Equal("https://github.com/rami2076/moost/releases/tag/v1.0.3-windows", update.Url);
        Assert.Equal(1, handler.Calls);
    }

    [Fact]
    public async Task SameOrOlderVersion_IsNotReported()
    {
        var same = Create("1.0.3", _ => Redirect("v1.0.3-windows"), out _);
        var older = Create("1.0.3", _ => Redirect("v1.0.2-windows"), out _);

        Assert.Null(await same.CheckAsync());
        Assert.Null(await older.CheckAsync());
    }

    [Fact]
    public async Task MacOsTags_AreIgnored()
    {
        var checker = Create("1.0.2", _ => Redirect("v2.4.0-macos"), out _);

        Assert.Null(await checker.CheckAsync());
    }

    [Fact]
    public async Task NonRedirectResponse_IsSilent()
    {
        var checker = Create("1.0.2", _ => new HttpResponseMessage(HttpStatusCode.OK), out _);

        Assert.Null(await checker.CheckAsync());
    }

    [Fact]
    public async Task NetworkError_IsSilent()
    {
        var checker = Create("1.0.2", _ => throw new HttpRequestException("offline"), out _);

        Assert.Null(await checker.CheckAsync());
    }

    [Fact]
    public async Task Throttle_SkipsNetworkWithinTheInterval()
    {
        var now = new DateTime(2026, 10, 25, 12, 0, 0, DateTimeKind.Utc);
        var handler = new StubHandler(_ => Redirect("v1.0.3-windows"));
        var checker = new UpdateChecker("1.0.2", new HttpClient(handler), () => now);

        var first = await checker.CheckAsync();
        var second = await checker.CheckAsync();

        Assert.NotNull(first);
        Assert.Equal(first, second); // 間隔内は前回の結果を返す
        Assert.Equal(1, handler.Calls);

        // 5 分経つと再取得する
        now = now.AddMinutes(6);
        _ = await checker.CheckAsync();
        Assert.Equal(2, handler.Calls);
    }

    [Theory]
    [InlineData("v1.0.3-windows", "1.0.3", true)]
    [InlineData("v10.20.30-windows", "10.20.30", true)]
    [InlineData("v2.4.0-macos", "", false)]
    [InlineData("v1.0.0-rc1-windows", "", false)]
    [InlineData("v1.0-windows", "", false)]
    [InlineData("1.0.3-windows", "", false)]
    public void TryParseWindowsTag_ValidatesPlatformAndSemver(string tag, string expected, bool ok)
    {
        Assert.Equal(ok, UpdateChecker.TryParseWindowsTag(tag, out var semver));
        if (ok)
        {
            Assert.Equal(expected, semver);
        }
    }

    [Theory]
    [InlineData("1.0.3", "1.0.2", 1)]
    [InlineData("1.0.2", "1.0.3", -1)]
    [InlineData("1.0.3", "1.0.3", 0)]
    [InlineData("2.0.0", "1.9.9", 1)]
    [InlineData("1.10.0", "1.9.0", 1)]
    public void CompareSemver_ComparesNumerically(string left, string right, int expectedSign)
    {
        Assert.Equal(expectedSign, Math.Sign(UpdateChecker.CompareSemver(left, right)));
    }

    [Fact]
    public void UpdateGuidance_DetectsWingetManagedInstall()
    {
        var wingetPath = @"C:\Users\me\AppData\Local\Microsoft\WinGet\Packages\rami2076.Moost_1.0.0_x64__abc\Moost.exe";
        var manualPath = @"C:\Users\me\AppData\Local\Programs\Moost\Moost.exe";

        Assert.True(UpdateGuidance.IsWingetManaged(wingetPath));
        Assert.False(UpdateGuidance.IsWingetManaged(manualPath));
        Assert.False(UpdateGuidance.IsWingetManaged(null));

        Assert.Equal("winget upgrade --id rami2076.Moost -e", UpdateGuidance.CommandFor(wingetPath));
        Assert.Null(UpdateGuidance.CommandFor(manualPath));
    }
}
