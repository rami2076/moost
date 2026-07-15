import 'dart:convert';
import 'dart:io';

/// `~/.codex/history.jsonl` を集約した 1 セッション分の元データ。
///
/// Claude Code と違い history 行はプロジェクトパスを持たないため、
/// [RecentSession] を作るにはセッション本体（rollout JSONL）の
/// `session_meta.cwd` を別途引く必要がある（CodexRolloutReader）。
class CodexHistoryEntry {
  final String sessionId;
  final String lastPrompt;
  final DateTime updatedAt;

  const CodexHistoryEntry({
    required this.sessionId,
    required this.lastPrompt,
    required this.updatedAt,
  });
}

/// `~/.codex/history.jsonl` を集約して直近セッション一覧の元データを作る。
///
/// history.jsonl は 1 行 = 1 プロンプトの JSONL
/// （`session_id` / `ts`（epoch 秒）/ `text`）。
/// 内部フォーマット変更でクラッシュしないよう、パースできない行はスキップする。
class CodexHistoryReader {
  final File historyFile;

  /// このマーカーで始まるプロンプトのセッションは一覧から除外する
  /// （要約実行の混入防止。ClaudeCodeAdapter と同じ仕組み）。
  final String excludeMarker;

  CodexHistoryReader({
    required this.historyFile,
    required this.excludeMarker,
  });

  /// 全セッションを最新順で返す。呼び出し側が rollout の有無で
  /// 間引くため、ここでは limit を切らない。
  Future<List<CodexHistoryEntry>> aggregatedEntries() async {
    if (!await historyFile.exists()) {
      return [];
    }
    final List<String> lines;
    try {
      lines = await historyFile.readAsLines();
    } on FileSystemException {
      return [];
    }

    // session_id 単位に集約し、最新 ts の行を採用する
    final latestBySession = <String, _HistoryLine>{};
    for (final line in lines) {
      final entry = _parseLine(line);
      if (entry == null) {
        continue;
      }
      if (entry.text.startsWith(excludeMarker)) {
        continue;
      }
      final existing = latestBySession[entry.sessionId];
      if (existing == null || entry.ts > existing.ts) {
        latestBySession[entry.sessionId] = entry;
      }
    }

    final entries = latestBySession.values.toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));

    return entries
        .map((entry) => CodexHistoryEntry(
              sessionId: entry.sessionId,
              lastPrompt: entry.text,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                entry.ts * 1000,
                isUtc: true,
              ),
            ))
        .toList();
  }

  _HistoryLine? _parseLine(String line) {
    if (line.trim().isEmpty) {
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
    final sessionId = decoded['session_id'];
    final ts = decoded['ts'];
    final text = decoded['text'];
    if (sessionId is! String || ts is! num || text is! String) {
      return null;
    }
    return _HistoryLine(
      sessionId: sessionId,
      ts: ts.toInt(),
      text: text,
    );
  }
}

class _HistoryLine {
  final String sessionId;
  final int ts;
  final String text;

  const _HistoryLine({
    required this.sessionId,
    required this.ts,
    required this.text,
  });
}
