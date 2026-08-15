import 'dart:io';

/// `brew` コマンドのパスを解決する（ClaudePathResolver / CodexPathResolver
/// と同じ 3 段構え。GUI アプリは PATH が最小限になるため）。
class BrewPathResolver {
  static const _knownAbsolutePaths = [
    '/opt/homebrew/bin/brew',
    '/usr/local/bin/brew',
  ];

  Future<String?> resolve() async {
    for (final path in _knownAbsolutePaths) {
      if (await File(path).exists()) {
        return path;
      }
    }
    try {
      final result = await Process.run('zsh', ['-lc', 'command -v brew']);
      if (result.exitCode != 0) {
        return null;
      }
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    } on ProcessException {
      return null;
    }
  }
}

/// brew 経由での自己更新実行に失敗したときに投げる。
class BrewUpdateException implements Exception {
  final String message;

  const BrewUpdateException(this.message);

  @override
  String toString() => 'BrewUpdateException: $message';
}

/// `brew update && brew upgrade --cask moost` を実行する。
///
/// 進捗は brew の CLI 出力に数値（%）が含まれないため取得できない。
/// 呼び出し側は不確定インジケーターで「実行中」だけを示す想定。
class BrewUpdater {
  final BrewPathResolver _pathResolver;

  /// 壊れて残った `/Applications/Moost.app` の削除を差し替え可能にする
  /// （テスト用）。
  final Future<void> Function() removeBrokenApp;

  BrewUpdater({
    BrewPathResolver? pathResolver,
    Future<void> Function()? removeBrokenApp,
  })  : _pathResolver = pathResolver ?? BrewPathResolver(),
        removeBrokenApp = removeBrokenApp ?? _defaultRemoveBrokenApp;

  static Future<void> _defaultRemoveBrokenApp() async {
    final dir = Directory('/Applications/Moost.app');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> run() async {
    final brewPath = await _pathResolver.resolve();
    if (brewPath == null) {
      throw const BrewUpdateException('brew command not found');
    }

    await _runStep(brewPath, ['update']);
    await _runStep(brewPath, ['upgrade', '--cask', 'moost']);
  }

  /// 中断されたアップグレードで壊れた Caskroom 状態からの復旧
  /// （Issue #58）。`brew reinstall --cask moost` を試し、空になった
  /// `/Applications/Moost.app` が邪魔で失敗する場合はそれを取り除いて
  /// 再試行する。
  Future<void> repair() async {
    final brewPath = await _pathResolver.resolve();
    if (brewPath == null) {
      throw const BrewUpdateException('brew command not found');
    }

    try {
      await _runStep(brewPath, ['reinstall', '--cask', 'moost']);
    } on BrewUpdateException {
      await removeBrokenApp();
      await _runStep(brewPath, ['reinstall', '--cask', 'moost']);
    }
  }

  Future<void> _runStep(String brewPath, List<String> arguments) async {
    final Process process;
    try {
      process = await Process.start(brewPath, arguments);
    } on ProcessException catch (e) {
      throw BrewUpdateException('failed to start brew: ${e.message}');
    }

    // exitCode を待つ前に両ストリームを EOF まで読み切る
    // （claude_summarizer.dart と同じ理由: パイプバッファ詰まりの回避）
    final stdoutFuture = process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).join();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      final detail = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
      throw BrewUpdateException(
          'brew ${arguments.join(' ')} exited with $exitCode: $detail');
    }
  }
}
