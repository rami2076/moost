import 'dart:convert';
import 'dart:io';

import 'codex_rollout_reader.dart';

/// rollout JSONL から直近 N ラリーの会話抜粋を取り出す。
///
/// ラリー = ユーザープロンプト 1 つと、それに続くアシスタント応答のまとまり
/// （Claude の TranscriptExtractor と同じ定義）。
/// 対象は `response_item` の user / assistant メッセージ。
/// Codex はシステム由来のコンテキストも user メッセージとして記録するため、
/// 既知のタグで始まるものは除外する。
class CodexTranscriptExtractor {
  final CodexRolloutReader rolloutReader;

  CodexTranscriptExtractor({required this.rolloutReader});

  /// Codex が user ロールで記録するシステム由来テキストの既知プレフィックス。
  static const _systemUserPrefixes = [
    '<environment_context>',
    '<user_instructions>',
    '<user_action>',
    '<turn_aborted>',
    '<permissions',
  ];

  Future<String?> extract(String sessionId, {int rallies = 1}) async {
    final index = await rolloutReader.scan();
    final rolloutFile = index[sessionId];
    if (rolloutFile == null) {
      return null;
    }

    final collected = <_Rally>[];
    Stream<String> lines;
    try {
      lines = rolloutFile
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
    // 安いフィルタ: メッセージを含みうる response_item 行だけを対象にする
    if (!line.contains('"type":"response_item"') ||
        !line.contains('"type":"message"')) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> ||
        decoded['type'] != 'response_item') {
      return null;
    }
    final payload = decoded['payload'];
    if (payload is! Map<String, Object?> || payload['type'] != 'message') {
      return null;
    }
    final role = payload['role'];
    if (role != 'user' && role != 'assistant') {
      return null;
    }
    final text = _extractText(payload['content']);
    if (text == null || text.isEmpty) {
      return null;
    }
    if (role == 'user' &&
        _systemUserPrefixes.any((prefix) => text.startsWith(prefix))) {
      return null;
    }
    return _Message(role: role as String, text: text);
  }

  /// content はブロック配列（`{"type":"input_text"|"output_text","text":...}`）。
  String? _extractText(Object? content) {
    if (content is! List<Object?>) {
      return null;
    }
    final parts = <String>[];
    for (final block in content) {
      if (block is! Map<String, Object?>) {
        continue;
      }
      final type = block['type'];
      if ((type == 'input_text' || type == 'output_text') &&
          block['text'] is String) {
        parts.add(block['text'] as String);
      }
    }
    return parts.isEmpty ? null : parts.join('\n');
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
