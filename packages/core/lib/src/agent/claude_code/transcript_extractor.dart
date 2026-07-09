import 'dart:convert';
import 'dart:io';

/// セッション JSONL から直近 N ラリーの会話抜粋を取り出す。
///
/// ラリー = ユーザープロンプト 1 つと、それに続くアシスタント応答のまとまり。
/// パースできない行・関係ない行（ツール実行やサイドチェーン等）はスキップする。
class TranscriptExtractor {
  final Directory projectsDir;

  TranscriptExtractor({required this.projectsDir});

  Future<String?> extract(String sessionId, {int rallies = 1}) async {
    final sessionFile = await _findSessionFile(sessionId);
    if (sessionFile == null) {
      return null;
    }

    final collected = <_Rally>[];
    Stream<String> lines;
    try {
      lines = sessionFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
    } on FileSystemException {
      return null;
    }

    await for (final line in lines) {
      final message = _parseMessage(line);
      if (message == null) {
        continue;
      }
      if (message.role == 'user') {
        collected.add(_Rally(userText: message.text));
        // メモリを抑えるため保持は直近分だけにする
        if (collected.length > rallies) {
          collected.removeAt(0);
        }
      } else if (collected.isNotEmpty) {
        collected.last.assistantTexts.add(message.text);
      }
    }

    if (collected.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    for (final rally in collected) {
      buffer.writeln('User: ${rally.userText}');
      for (final text in rally.assistantTexts) {
        buffer.writeln('Assistant: $text');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  _Message? _parseMessage(String line) {
    // 安いフィルタ: user / assistant メッセージ行だけを対象にする
    if (!line.contains('"type":"user"') &&
        !line.contains('"type":"assistant"')) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded['isSidechain'] == true) {
      return null;
    }
    final type = decoded['type'];
    if (type != 'user' && type != 'assistant') {
      return null;
    }
    final message = decoded['message'];
    if (message is! Map<String, Object?>) {
      return null;
    }
    final text = _extractText(message['content']);
    if (text == null || text.isEmpty) {
      return null;
    }
    return _Message(role: type as String, text: text);
  }

  /// content は文字列またはブロック配列（`{"type":"text","text":...}` 等）。
  String? _extractText(Object? content) {
    if (content is String) {
      return content;
    }
    if (content is List<Object?>) {
      final parts = <String>[];
      for (final block in content) {
        if (block is Map<String, Object?> &&
            block['type'] == 'text' &&
            block['text'] is String) {
          parts.add(block['text'] as String);
        }
      }
      if (parts.isNotEmpty) {
        return parts.join('\n');
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
}

class _Message {
  final String role;
  final String text;

  const _Message({required this.role, required this.text});
}

class _Rally {
  final String userText;
  final List<String> assistantTexts = [];

  _Rally({required this.userText});
}
