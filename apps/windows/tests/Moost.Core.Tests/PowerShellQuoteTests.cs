using Moost.Core;

namespace Moost.Core.Tests;

/// <summary>
/// conformance G1（シェル escape・文字列レベル）。
/// POSIX 版の <c>shell_escape_test.dart</c> に対応する Windows（PowerShell）版。
/// </summary>
public class PowerShellQuoteTests
{
    [Fact]
    public void WrapsPlainStringInSingleQuotes()
    {
        Assert.Equal("'C:\\work\\project'", PowerShellQuote.Quote("C:\\work\\project"));
    }

    [Fact]
    public void EscapesSingleQuotesByDoubling()
    {
        Assert.Equal("'it''s'", PowerShellQuote.Quote("it's"));
    }

    [Theory]
    [InlineData("we`ird", "'we`ird'")]                       // バッククォートは単一引用符内では literal
    [InlineData("$HOME dir", "'$HOME dir'")]                 // 変数展開しない
    [InlineData("a; b", "'a; b'")]                           // 文の区切りにならない
    [InlineData("a | b", "'a | b'")]                         // パイプにならない
    [InlineData("a && b", "'a && b'")]                       // 連結にならない
    [InlineData("a > out.txt", "'a > out.txt'")]             // リダイレクトにならない
    [InlineData("a < in.txt", "'a < in.txt'")]               // 入力リダイレクトにならない
    [InlineData("$(whoami)", "'$(whoami)'")]                 // 部分式展開しない
    [InlineData("@(1,2)", "'@(1,2)'")]                       // 配列式にならない
    [InlineData("%PATH%", "'%PATH%'")]                       // cmd 変数展開もしない
    [InlineData("", "''")]
    [InlineData(" ", "' '")]
    public void KeepsDangerousCharactersLiteral(string value, string expected)
    {
        Assert.Equal(expected, PowerShellQuote.Quote(value));
    }

    [Fact]
    public void KeepsNewlinesInsideQuotes()
    {
        Assert.Equal("'a\nb'", PowerShellQuote.Quote("a\nb"));
    }

    [Fact]
    public void NullBecomesEmptyQuotedString()
    {
        Assert.Equal("''", PowerShellQuote.Quote(null));
    }

    [Fact]
    public void EscapesEveryQuoteInSequence()
    {
        // 3 個の ' → それぞれ二重化で 6 個 + 外側の 2 個 = 8 個
        Assert.Equal("''''''''", PowerShellQuote.Quote("'''"));
    }
}
