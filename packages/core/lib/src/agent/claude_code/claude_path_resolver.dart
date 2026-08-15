import 'dart:io';

/// `claude` コマンドのパスを解決する。
///
/// GUI アプリから起動すると PATH が最小限になり bare な `claude` が
/// 解決できないため、3 段構えで解決する（design.md 7 章ハマりどころ 1）:
/// 1. 設定での手動上書き
/// 2. 既知パスの探索
/// 3. 対話シェルでの解決
class ClaudePathResolver {
  final String home;

  /// 対話ログインシェル経由の解決を差し替え可能にする（テスト用）。
  final Future<ProcessResult> Function(List<String> args) runZsh;

  /// 既知パスの実在確認を差し替え可能にする（テスト用。実マシンに
  /// たまたま /opt/homebrew/bin/claude 等が存在すると、ログインシェル
  /// フォールバックまでテストで到達できなくなるため）。
  final Future<bool> Function(String path) fileExists;

  ClaudePathResolver({
    String? home,
    Future<ProcessResult> Function(List<String> args)? runZsh,
    Future<bool> Function(String path)? fileExists,
  })  : home = home ?? Platform.environment['HOME'] ?? '',
        runZsh = runZsh ?? ((args) => Process.run('zsh', args)),
        fileExists = fileExists ?? ((path) => File(path).exists());

  static const _knownRelativePaths = [
    '.local/bin/claude',
    'bin/claude',
    '.claude/local/claude',
  ];

  static const _knownAbsolutePaths = [
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ];

  Future<String?> resolve({String override = ''}) async {
    if (override.isNotEmpty) {
      return _expandTilde(override);
    }

    for (final relative in _knownRelativePaths) {
      final path = '$home/$relative';
      if (await fileExists(path)) {
        return path;
      }
    }
    for (final path in _knownAbsolutePaths) {
      if (await fileExists(path)) {
        return path;
      }
    }

    return _resolveViaLoginShell();
  }

  Future<String?> _resolveViaLoginShell() async {
    try {
      // -i（対話シェル）を付けないと .zshrc を読まないため、nvm/pyenv/asdf
      // 等が PATH を .zshrc 側で追加している環境では claude を見つけられ
      // なかった（Issue #53）。-lc では原理的に解決できない
      final result = await runZsh(['-lic', 'command -v claude']);
      if (result.exitCode != 0) {
        return null;
      }
      // -i を付けたことで .zshrc 自体が実行され、その中の echo 等の出力が
      // 標準出力に混ざることがある。最終行だけを実行結果として採用する
      // （末尾の改行で split すると最後が空文字列になるため、先に
      // trim してから split する）
      final lines = (result.stdout as String).trim().split('\n');
      final path = lines.last.trim();
      return path.isEmpty ? null : path;
    } on ProcessException {
      return null;
    }
  }

  String _expandTilde(String path) {
    if (path == '~') {
      return home;
    }
    if (path.startsWith('~/')) {
      return '$home${path.substring(1)}';
    }
    return path;
  }
}
