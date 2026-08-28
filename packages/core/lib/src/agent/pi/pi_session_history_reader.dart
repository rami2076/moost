import 'dart:convert';
import 'dart:io';

/// pi（この coding agent）セッション 1 件分の抽出結果。
class PiSessionEntry {
  final String sessionId;
  final String projectPath;
  final String lastPrompt;
  final DateTime updatedAt;

  const PiSessionEntry({
    required this.sessionId,
    required this.projectPath,
    required this.lastPrompt,
    required this.updatedAt,
  });
}

/// pi のセッション保存（`~/.pi/agent/sessions/<cwd>/<ts>_<id>.jsonl`）を読む。
///
/// JSONL の先頭行にセッションヘッダ（`type: session`）があり、
/// `id` / `cwd` / 開始時刻を持つ。それ以降はツリー構造のイベント行で、
/// `message`（user/assistant）が会話本体。
class PiSessionHistoryReader {
  final Directory sessionsDir;

  PiSessionHistoryReader({Directory? sessionsDir})
      : sessionsDir =
            sessionsDir ??
                Directory(
                  '${Platform.environment['HOME'] ?? ''}/.pi/agent/sessions',
                );

  /// 全セッションを新しい順で返す。
  Future<List<PiSessionEntry>> recentSessions({int limit = 20}) async {
    if (!await sessionsDir.exists()) {
      return [];
    }
    final files = await _collectSessionFiles(sessionsDir);

    final entries = <PiSessionEntry>[];
    for (final file in files) {
      final data = await _scanFile(file);
      if (data != null) {
        entries.add(data);
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.take(limit).toList();
  }

  /// 再帰的に `sessions` 配下の `.jsonl` を集める（安定順にする）。
  Future<List<File>> _collectSessionFiles(Directory dir) async {
    final out = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        out.add(entity);
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// 1 ファイルからヘッダ・最終プロンプト・更新時刻を読む。
  Future<PiSessionEntry?> _scanFile(File file) async {
    final List<String> lines;
    try {
      lines = await file.readAsLines();
    } on FileSystemException {
      return null;
    }
    if (lines.isEmpty) {
      return null;
    }

    final header = _parseHeader(lines.first);
    if (header == null) {
      return null;
    }

    // 末尾の message から「最後のユーザー発言」と「最新時刻」を拾う
    var lastUserText = '';
    var newest = header.timestamp;
    for (final line in lines.skip(1)) {
      final ts = _parseMessageTimestamp(line);
      if (ts != null && ts.isAfter(newest)) {
        newest = ts;
      }
      final userText = _extractUserText(line);
      if (userText != null && userText.isNotEmpty) {
        lastUserText = userText;
      }
    }

    return PiSessionEntry(
      sessionId: header.id,
      projectPath: header.cwd,
      lastPrompt: lastUserText,
      updatedAt: newest,
    );
  }

  // --- パース ---

  _PiHeader? _parseHeader(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      if (decoded['type'] != 'session') {
        return null;
      }
      final id = decoded['id'];
      final cwd = decoded['cwd'];
      final timestamp = decoded['timestamp'];
      if (id is! String) {
        return null;
      }
      return _PiHeader(
        id: id,
        cwd: cwd is String ? cwd : '',
        timestamp: DateTime.tryParse(timestamp is String ? timestamp : '') ??
            DateTime.utc(1970),
      );
    } on FormatException {
      return null;
    }
  }

  /// message 行からロール user のテキスト（content の text 型）を返す。
  String? _extractUserText(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      if (decoded['type'] != 'message') {
        return null;
      }
      final message = decoded['message'];
      if (message is! Map<String, Object?>) {
        return null;
      }
      if (message['role'] != 'user') {
        return null;
      }
      final content = message['content'];
      if (content is! List<Object?>) {
        return null;
      }
      final texts = <String>[];
      for (final part in content) {
        if (part is Map<String, Object?> && part['type'] == 'text') {
          final text = part['text'];
          if (text is String) {
            texts.add(text.trim());
          }
        }
      }
      if (texts.isEmpty) {
        return null;
      }
      return texts.join(' ');
    } on FormatException {
      return null;
    }
  }

  DateTime? _parseMessageTimestamp(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final timestamp = decoded['timestamp'];
      return DateTime.tryParse(timestamp is String ? timestamp : '');
    } on FormatException {
      return null;
    }
  }
}

class _PiHeader {
  final String id;
  final String cwd;
  final DateTime timestamp;

  const _PiHeader({
    required this.id,
    required this.cwd,
    required this.timestamp,
  });
}
