import 'dart:convert';
import 'dart:io';

/// 人が読める JSON ファイルの読み書き基盤。
///
/// - 書き込みは一時ファイル → リネームのアトミック方式
///   （書き込み中のクラッシュで本体を壊さない）
/// - 読み込み時に JSON として壊れていたら、上書きせず
///   `<name>.corrupt-<timestamp>` へ退避して null を返す
///   （データを黙って失わない。design.md 4 章）
class JsonFileStore {
  final File file;

  JsonFileStore(this.file);

  Future<Map<String, Object?>?> read() async {
    if (!await file.exists()) {
      return null;
    }
    // 読み取りエラー（権限等）はここで握りつぶさない。null を返すと
    // 呼び出し側が「空のストア」とみなして上書き保存し、既存データを失う
    final content = await file.readAsString();
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      await _quarantine();
      return null;
    } on FormatException {
      await _quarantine();
      return null;
    }
  }

  Future<void> write(Map<String, Object?> json) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString('${encoder.convert(json)}\n', flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _quarantine() async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-');
    await file.rename('${file.path}.corrupt-$stamp');
  }
}
