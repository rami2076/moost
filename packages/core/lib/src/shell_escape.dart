/// POSIX シェル向けに文字列をシングルクォートでエスケープする。
///
/// バッククォート・`$`・スペース等を含むパスでもコマンドが壊れないこと
/// （design.md 7 章ハマりどころ 4）。
String shellEscape(String value) => "'${value.replaceAll("'", r"'\''")}'";
