/// Claude Code が自身のプロセスに設定する内部環境変数の判定・除去
/// ユーティリティ（Issue #52）。
///
/// Moost が `claude` を子プロセスとして起動する際、Moost 自身のプロセスが
/// これらの変数を（Claude Code のターミナルセッションから `open`/直接実行
/// で起動された等の経路で）保持していると、fork/exec でそのまま子へ
/// 継承されてしまう。Claude Code は `CLAUDE_CODE_CHILD_SESSION=1` 等を
/// 見ると「自分は子セッションだ」と誤認識し、transcript の保存を止める
/// （実測: `--resume` 一覧から消える・履歴が残らない）。
///
/// 固定の変数名リストだけに頼ると、Claude Code 側が将来新しい内部変数を
/// 追加するたびにコードの追従が必要になる。実際に稼働中のセッションの
/// 環境を調べた際、事前に把握していなかった `CLAUDE_PID` が新たに見つかって
/// おり、この懸念は実証済み。そのため `CLAUDE_` プレフィックスによる判定を
/// 主とし、パターンに乗らない既知の変数だけを個別リストで補う。
library;

/// プレフィックスにマッチしない、既知の Claude Code 関連変数。
const claudeCodeNonPrefixedEnvVars = {'CLAUDECODE', 'AI_AGENT'};

/// [key] が Claude Code 関連の内部環境変数とみなせるか。
///
/// `CLAUDE_` で始まる変数は将来 Claude Code 側が新設したものも自動的に
/// 対象になる（例: 本来は事前リストになかった `CLAUDE_PID` もこれで拾える）。
bool isClaudeCodeInternalEnvVar(String key) {
  if (claudeCodeNonPrefixedEnvVars.contains(key)) {
    return true;
  }
  return key.startsWith('CLAUDE_');
}

/// [env] から Claude Code 関連の内部環境変数だけを取り除いた Map を返す。
///
/// `Process.start`/`Process.run` の `environment` にそのまま渡せる
/// （`Platform.environment` を直接起動する経路向け。プレフィックスマッチで
/// 判定するため、将来増える変数にも追従できる）。
Map<String, String> withoutClaudeCodeInternalEnv(Map<String, String> env) {
  return Map.fromEntries(
    env.entries.where((entry) => !isClaudeCodeInternalEnvVar(entry.key)),
  );
}

/// これまでに実際に観測された Claude Code 内部環境変数名（決め打ちリスト）。
///
/// AppleScript 経由でターミナルへ文字列としてコマンドを渡す経路
/// （[TerminalLauncher]）では、Dart コード側からプロセス環境を直接
/// 制御できないため、[isClaudeCodeInternalEnvVar] のような動的な
/// プレフィックスマッチをコマンド文字列に埋め込めない。そのためこちらは
/// 決め打ちリストにならざるを得ない（新しい変数が見つかったら追加する）。
const knownClaudeCodeEnvVarNames = [
  'CLAUDECODE',
  'CLAUDE_CODE_ENTRYPOINT',
  'CLAUDE_CODE_SESSION_ID',
  'CLAUDE_CODE_CHILD_SESSION',
  'CLAUDE_CODE_ENABLE_TELEMETRY',
  'CLAUDE_EFFORT',
  'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE',
  'CLAUDE_CODE_EXECPATH',
  'CLAUDE_PID',
  'AI_AGENT',
];

/// `env -u VAR1 -u VAR2 ... ` の形のシェルコマンドプレフィックス。
///
/// [knownClaudeCodeEnvVarNames] の変数が未設定でもエラーにならないため、
/// 環境が汚染されているかどうかを問わず常に付けてよい。
String claudeCodeEnvUnsetPrefix() =>
    'env ${knownClaudeCodeEnvVarNames.map((name) => '-u $name').join(' ')} ';
