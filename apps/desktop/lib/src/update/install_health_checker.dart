import 'dart:io';

/// Homebrew Cask 経由のアップグレードが中断された結果、アプリ本体が
/// 壊れた状態になっていないかを調べる（Issue #58）。
///
/// 起動中の Moost プロセス自体は、ファイルシステム上の実体が消えても
/// メモリ上で動き続けるため、壊れたことに気づきにくい。次回の起動が
/// できなくなる前に、以下の 2 点を独立にチェックする:
/// 1. 自分自身の実行ファイルが存在するか（`/Applications/Moost.app` が
///    空になっていないか）
/// 2. Caskroom 内に `*.upgrading` という中断された一時ディレクトリが
///    残っていないか（brew の内部状態と実体がズレている兆候）
class InstallHealthChecker {
  static const _executablePath =
      '/Applications/Moost.app/Contents/MacOS/moost_desktop';

  static const _caskroomDirs = [
    '/opt/homebrew/Caskroom/moost',
    '/usr/local/Caskroom/moost',
  ];

  /// 実行ファイルの実在確認を差し替え可能にする（テスト用）。
  final Future<bool> Function(String path) fileExists;

  /// Caskroom ディレクトリ一覧の取得を差し替え可能にする（テスト用）。
  final Future<List<String>> Function(String dirPath) listEntries;

  InstallHealthChecker({
    Future<bool> Function(String path)? fileExists,
    Future<List<String>> Function(String dirPath)? listEntries,
  })  : fileExists = fileExists ?? ((path) => File(path).exists()),
        listEntries = listEntries ?? _defaultListEntries;

  static Future<List<String>> _defaultListEntries(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const [];
    }
    return dir
        .list()
        .map((entity) => entity.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toList();
  }

  /// 壊れていれば true。
  Future<bool> isBroken() async {
    if (!await fileExists(_executablePath)) {
      return true;
    }
    for (final caskroomDir in _caskroomDirs) {
      final entries = await listEntries(caskroomDir);
      if (entries.any((name) => name.endsWith('.upgrading'))) {
        return true;
      }
    }
    return false;
  }
}
