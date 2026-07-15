import 'dart:convert';
import 'dart:io';

/// `~/.codex/sessions/` 配下の rollout JSONL を扱う。
///
/// セッション本体は `sessions/YYYY/MM/DD/rollout-<日時>-<sessionId>.jsonl`。
/// 日付ディレクトリの構造には依存せず、「ファイル名末尾が
/// `-<sessionId>.jsonl`」という性質だけを使って再帰走査で見つける
/// （Claude の AiTitleReader と同じ方針）。
class CodexRolloutReader {
  final Directory sessionsDir;

  CodexRolloutReader({required this.sessionsDir});

  static final _rolloutName = RegExp(
    r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
  );

  /// sessionId → rollout ファイルの索引を作る。
  ///
  /// 同一 sessionId の rollout が複数ある場合（resume 等）は、
  /// ファイル名に日時が入っている性質を使い辞書順で最新を採用する。
  Future<Map<String, File>> scan() async {
    final index = <String, File>{};
    if (!await sessionsDir.exists()) {
      return index;
    }
    await for (final entity
        in sessionsDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final match = _rolloutName.firstMatch(name);
      if (match == null) {
        continue;
      }
      final sessionId = match.group(1)!;
      final existing = index[sessionId];
      if (existing == null ||
          _fileName(existing).compareTo(name) < 0) {
        index[sessionId] = entity;
      }
    }
    return index;
  }

  /// rollout 先頭の `session_meta` 行からセッションの作業ディレクトリを返す。
  ///
  /// session_meta は通常 1 行目だが、多少ずれても拾えるよう先頭数行を見る。
  /// 見つからない・読めない場合は null。
  Future<String?> readCwd(File rolloutFile) async {
    const maxHeadLines = 10;
    Stream<String> lines;
    try {
      lines = rolloutFile
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
    } on FileSystemException {
      return null;
    }

    var count = 0;
    try {
      await for (final line in lines) {
        if (++count > maxHeadLines) {
          break;
        }
        if (!line.contains('"session_meta"')) {
          continue;
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(line);
        } on FormatException {
          continue;
        }
        if (decoded is! Map<String, Object?> ||
            decoded['type'] != 'session_meta') {
          continue;
        }
        final payload = decoded['payload'];
        if (payload is! Map<String, Object?>) {
          continue;
        }
        final cwd = payload['cwd'];
        return cwd is String ? cwd : null;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  String _fileName(File file) => file.uri.pathSegments.last;
}
