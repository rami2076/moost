import 'package:file_selector/file_selector.dart';

/// OS のフォルダ選択ダイアログを開く。
///
/// `file_selector`（publisher: flutter.dev）を使う。macOS 実装は
/// `NSOpenPanel` をポップオーバー自身のウィンドウへ `beginSheetModal(for:)`
/// でシート表示するため、外部プロセス（旧: osascript の `choose folder`）と
/// 違い、ダイアログ表示中にポップオーバーがフォーカスを失って隠れることが
/// ない。Windows/Linux 対応（Issue #15）でも同じ API がそのまま使える。
class FolderPicker {
  /// 実際のダイアログ呼び出しを差し替え可能にする（テスト用）。
  final Future<String?> Function() getDirectoryPathFn;

  FolderPicker({Future<String?> Function()? getDirectoryPathFn})
      : getDirectoryPathFn = getDirectoryPathFn ?? getDirectoryPath;

  /// 選ばれたディレクトリの絶対パスを返す。ユーザーがキャンセルしたら null。
  Future<String?> pick() => getDirectoryPathFn();
}
