import 'dart:io';

/// 同梱された MCP サーバーバイナリ（`moost-mcp`）の実体パスを解決する
/// （Issue #45）。
///
/// release.yml が `dart compile exe` でビルドした `moost-mcp` を、署名前に
/// `Moost.app/Contents/Resources/` へコピーしている。実行中のアプリ自身の
/// `Platform.resolvedExecutable`（`.../Moost.app/Contents/MacOS/moost_desktop`）
/// から兄弟ディレクトリの `Resources/moost-mcp` を導出するだけで、
/// インストール先（`/Applications` に限らない）に依存せず正しいパスが取れる。
///
/// 開発時（`flutter run`）のビルドにはこの同梱ステップが走っていないため、
/// [exists] は false を返す。
class McpBinaryLocator {
  final String _resolvedExecutable;

  McpBinaryLocator({String? resolvedExecutable})
      : _resolvedExecutable =
            resolvedExecutable ?? Platform.resolvedExecutable;

  /// `Moost.app/Contents/Resources/moost-mcp` の絶対パス。
  String get binaryPath {
    final macosDir = File(_resolvedExecutable).parent.path; // .../Contents/MacOS
    final contentsDir = Directory(macosDir).parent.path; // .../Contents
    return '$contentsDir/Resources/moost-mcp';
  }

  Future<bool> exists() => File(binaryPath).exists();
}
