import 'dart:io';

/// `codex` コマンドのパスを解決する。
///
/// GUI アプリから起動すると PATH が最小限になり bare な `codex` が
/// 解決できないため、ClaudePathResolver と同じ 3 段構えで解決する:
/// 1. 設定での手動上書き
/// 2. 既知パスの探索
/// 3. 対話シェルでの解決
class CodexPathResolver {
  final String home;

  CodexPathResolver({String? home})
      : home = home ?? Platform.environment['HOME'] ?? '';

  static const _knownRelativePaths = [
    '.local/bin/codex',
    'bin/codex',
  ];

  static const _knownAbsolutePaths = [
    '/opt/homebrew/bin/codex',
    '/usr/local/bin/codex',
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
        ['-lc', 'command -v codex'],
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
