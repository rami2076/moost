import 'dart:convert';
import 'dart:io';

/// pi セッション JSONL から、要約用のプレーンテキストを組み立てる。
///
/// pi は対話セッションをツリー構造の JSONL で保存しており、`message` 行の
/// `message.role`（user/assistant）と `content[]` の text 型をたどる。
/// ヘッドレス要約コマンドを持たないため、この抽出結果をそのまま要約として
/// 返す（PiAdapter.summarize）。API 消費ゼロ。
class PiTranscriptExtractor {
  final Directory sessionsDir;

  PiTranscriptExtractor({Directory? sessionsDir})
      : sessionsDir =
            sessionsDir ??
                Directory(
                  '${Platform.environment['HOME'] ?? ''}/.pi/agent/sessions',
                );

  /// セッション [sessionId] のやり取りをテキスト化して返す。
  /// 対象ファイルが見つからない場合は空文字列。
  ///
  /// - [full] が false: 末尾 [rallies] * 2 メッセージ（直近のやり取り）
  /// - [full] が true: セッション全体
  Future<String> extract({
    required String sessionId,
    bool full = false,
    int rallies = 1,
  }) async {
    final target = await _findSessionFile(sessionId);
    if (target == null) {
      return '';
    }
    final List<Object> messages;
    try {
      messages = await _readMessages(target);
    } on FileSystemException {
      return '';
    }
    if (messages.isEmpty) {
      return '';
    }

    final selected = full
        ? messages
        : messages.length > rallies * 2
            ? messages.sublist(messages.length - rallies * 2)
            : messages;

    final buffer = StringBuffer();
    for (final entry in selected) {
      final message = entry as _PiMessage;
      final t = message.text.trim();
      if (t.isEmpty) {
        continue;
      }
      buffer.writeln(message.role == 'user' ? 'User: $t' : 'Assistant: $t');
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// sessionId（ヘッダの id）が一致するセッションファイルを探す。
  Future<File?> _findSessionFile(String sessionId) async {
    if (!await sessionsDir.exists()) {
      return null;
    }
    // ファイル名に <ts>_<id>.jsonl 形式で id が入っているので先に照合
    final files = <File>[];
    await for (final entity
        in sessionsDir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        final name = entity.uri.pathSegments.last;
        if (name.contains('_$sessionId.jsonl')) {
          return entity;
        }
        files.add(entity);
      }
    }
    // フォールバック: ヘッダの id と照合
    for (final file in files) {
      final List<String> lines;
      try {
        lines = await file.readAsLines();
      } on FileSystemException {
        continue;
      }
      if (lines.isNotEmpty && lines.first.contains('"type":"session"')) {
        try {
          final decoded = jsonDecode(lines.first);
          if (decoded is Map<String, Object?> && decoded['id'] == sessionId) {
            return file;
          }
        } on FormatException {
          // 次へ
        }
      }
    }
    return null;
  }

  Future<List<Object>> _readMessages(File file) async {
    final lines = await file.readAsLines();
    final out = <Object>[];
    for (final line in lines) {
      final parsed = _parseMessage(line);
      if (parsed != null) {
        out.add(parsed);
      }
    }
    return out;
  }

  _PiMessage? _parseMessage(String line) {
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
      final role = message['role'];
      if (role != 'user' && role != 'assistant') {
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
      return _PiMessage(
        role: role == 'user' ? 'user' : 'assistant',
        text: texts.join('\n'),
      );
    } on FormatException {
      return null;
    }
  }
}

class _PiMessage {
  final String role;
  final String text;

  const _PiMessage({required this.role, required this.text});
}
