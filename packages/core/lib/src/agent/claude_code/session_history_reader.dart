import 'dart:convert';
import 'dart:io';

import '../../model/recent_session.dart';

/// `~/.claude/history.jsonl` を集約して直近セッション一覧の元データを作る。
///
/// history.jsonl は 1 行 = 1 プロンプトの JSONL
/// （`display` / `timestamp` / `project` / `sessionId`）。
/// 内部フォーマット変更でクラッシュしないよう、パースできない行はすべてスキップする
/// （design.md 3.1）。
class SessionHistoryReader {
  final File historyFile;

  /// 生成する [RecentSession] に刻むエージェント識別子。
  final String agentId;

  /// このマーカーで始まるプロンプトのセッションは一覧から除外する
  /// （要約用フォークセッションの混入防止。design.md 5 章）。
  final String excludeMarker;

  SessionHistoryReader({
    required this.historyFile,
    required this.agentId,
    required this.excludeMarker,
  });

  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    if (!await historyFile.exists()) {
      return [];
    }
    final List<String> lines;
    try {
      lines = await historyFile.readAsLines();
    } on FileSystemException {
      return [];
    }

    // sessionId 単位に集約し、最新 timestamp の行を採用する
    final latestBySession = <String, _HistoryEntry>{};
    for (final line in lines) {
      final entry = _parseLine(line);
      if (entry == null) {
        continue;
      }
      if (entry.display.startsWith(excludeMarker)) {
        continue;
      }
      final existing = latestBySession[entry.sessionId];
      if (existing == null || entry.timestamp > existing.timestamp) {
        latestBySession[entry.sessionId] = entry;
      }
    }

    final entries = latestBySession.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return entries.take(limit).map((entry) {
      return RecentSession(
        agentId: agentId,
        sessionId: entry.sessionId,
        projectPath: entry.project,
        lastPrompt: entry.display,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          entry.timestamp,
          isUtc: true,
        ),
      );
    }).toList();
  }

  _HistoryEntry? _parseLine(String line) {
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
    final display = decoded['display'];
    final timestamp = decoded['timestamp'];
    final project = decoded['project'];
    final sessionId = decoded['sessionId'];
    if (display is! String ||
        timestamp is! num ||
        project is! String ||
        sessionId is! String) {
      return null;
    }
    return _HistoryEntry(
      display: display,
      timestamp: timestamp.toInt(),
      project: project,
      sessionId: sessionId,
    );
  }
}

class _HistoryEntry {
  final String display;
  final int timestamp;
  final String project;
  final String sessionId;

  const _HistoryEntry({
    required this.display,
    required this.timestamp,
    required this.project,
    required this.sessionId,
  });
}
