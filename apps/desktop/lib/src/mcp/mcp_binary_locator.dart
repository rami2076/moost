import 'dart:io';

/// 同梱された MCP サーバーバイナリ（`moost-mcp`）の実体パスを解決する
/// （Issue #45）。
///
/// release.yml が `dart compile exe` でビルドした `moost-mcp` を、署名前に
/// `Moost.app/Contents/Resources/` へコピーしている（macOS）。実行中のアプリ
/// 自身の `Platform.resolvedExecutable` から兄弟ディレクトリを導出するだけで、
/// インストール先（`/Applications` に限らない）に依存せず正しいパスが取れる。
///
/// Linux（Q1: .deb）は `flutter build linux` の成果物レイアウト
/// （`build/linux/x64/release/bundle/moost_desktop` 直下に `moost-mcp` を
/// 同梱する）に合わせ、実行ファイルの親ディレクトリをそのまま使う。
///
/// 開発時（`flutter run`）のビルドにはこの同梱ステップが走っていないため、
/// [exists] は false を返す。
class McpBinaryLocator {
  final String _resolvedExecutable;

  /// テスト用にプラットフォーム分岐を固定できる。null なら実環境の判定を使う。
  final bool _isLinux;

  McpBinaryLocator({String? resolvedExecutable, bool? isLinux})
      : _resolvedExecutable =
            resolvedExecutable ?? Platform.resolvedExecutable,
        _isLinux = isLinux ?? Platform.isLinux;

  /// `moost-mcp` の絶対パス。
  String get binaryPath {
    if (_isLinux) {
      // Linux: 実行可能ファイルと同じディレクトリに同梱する
      return '${File(_resolvedExecutable).parent.path}/moost-mcp';
    }
    // macOS: `Moost.app/Contents/Resources/moost-mcp`
    final macosDir = File(_resolvedExecutable).parent.path; // .../Contents/MacOS
    final contentsDir = Directory(macosDir).parent.path; // .../Contents
    return '$contentsDir/Resources/moost-mcp';
  }

  Future<bool> exists() => File(binaryPath).exists();
}
