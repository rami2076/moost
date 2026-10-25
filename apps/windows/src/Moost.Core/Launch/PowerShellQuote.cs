namespace Moost.Core;

/// <summary>
/// PowerShell の単一引用符リテラルとして文字列をクォートする（conformance G1）。
///
/// PowerShell の <c>'...'</c> は「展開しない文字列」で、内側の <c>'</c> だけを
/// <c>''</c> に二重化すればよい。したがって <c>$</c> / バッククォート / <c>;</c> /
/// <c>|</c> / <c>&amp;&amp;</c> / <c>&gt;</c> / 改行 はすべてそのままの文字として扱われる
/// （リファレンス実装 <c>shell_escape.dart</c> の POSIX 版に対応する Windows 版）。
///
/// 設計上の制約: 生成するコマンド文字列には <b>二重引用符を使わない</b>。
/// 端末起動時（#103）に <c>wt.exe</c> / <c>powershell.exe</c> へ引数として渡すため、
/// 二重引用符が混ざると Windows のコマンドライン引用規則と二重にエスケープが掛かる。
/// </summary>
public static class PowerShellQuote
{
    /// <summary>単一引用符リテラルに変換する。</summary>
    public static string Quote(string? value) =>
        "'" + (value ?? string.Empty).Replace("'", "''", StringComparison.Ordinal) + "'";
}
