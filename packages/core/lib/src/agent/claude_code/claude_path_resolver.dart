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

  ClaudePathResolver({String? home})
      : home = home ?? Platform.environment['HOME'] ?? '';

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
      if (await File(path).exists()) {
        return path;
      }
    }
    for (final path in _knownAbsolutePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    return _resolveViaLoginShell();
  }

  Future<String?> _resolveViaLoginShell() async {
    try {
      final result = await Process.run(
        'zsh',
        ['-lc', 'command -v claude'],
      );
      if (result.exitCode != 0) {
        return null;
      }
      final path = (result.stdout as String).trim();
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
