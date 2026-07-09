import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// セッション JSONL の末尾から最新の ai-title を取り出す。
///
/// - ファイル特定はディレクトリ名のエンコード規則に依存せず、
///   「ファイル名が UUID で一意」という性質だけを使う（design.md 3.2）
/// - セッション JSONL は数十 MB になりうるため全読みせず、末尾チャンクだけ読む
/// - 逆順走査で最初にヒットしたものが最新（タイトルは会話中に更新される）
class AiTitleReader {
  final Directory projectsDir;
  final int tailBytes;

  AiTitleReader({
    required this.projectsDir,
    this.tailBytes = 64 * 1024,
  });

  Future<String?> latestAiTitle(String sessionId) async {
    final sessionFile = await _findSessionFile(sessionId);
    if (sessionFile == null) {
      return null;
    }
    final String tail;
    try {
      tail = await _readTail(sessionFile);
    } on FileSystemException {
      return null;
    }

    for (final line in tail.split('\n').reversed) {
      // 安いフィルタを先にかけ、含む行だけ JSON デコードする
      if (!line.contains('"ai-title"')) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) {
        continue;
      }
      if (decoded['type'] != 'ai-title') {
        continue;
      }
      final title = decoded['aiTitle'];
      if (title is String && title.isNotEmpty) {
        return title;
      }
    }
    return null;
  }

  Future<File?> _findSessionFile(String sessionId) async {
    if (!await projectsDir.exists()) {
      return null;
    }
    await for (final entity in projectsDir.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final candidate = File('${entity.path}/$sessionId.jsonl');
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String> _readTail(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final start = max(0, length - tailBytes);
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      // チャンク先頭がマルチバイト文字の途中でも落ちないようにする
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await raf.close();
    }
  }
}
