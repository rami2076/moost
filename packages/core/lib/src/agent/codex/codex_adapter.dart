import 'dart:io';

import '../../model/recent_session.dart';
import '../../shell_escape.dart';
import '../agent_adapter.dart';
import '../summarize_exception.dart';
import 'codex_history_reader.dart';
import 'codex_path_resolver.dart';
import 'codex_rollout_reader.dart';
import 'codex_summarizer.dart';
import 'codex_transcript_extractor.dart';

/// Codex CLI 向けの [AgentAdapter] 実装。
///
/// Claude Code との主な差分:
/// - history.jsonl（`session_id` / `ts` 秒 / `text`）はプロジェクトパスを
///   持たないため、rollout JSONL 先頭の `session_meta.cwd` から補完する
/// - ai-title 相当がないため、タイトルは常に最終プロンプトのフォールバック
/// - 要約は `codex exec --ephemeral`（直近）/ `codex exec resume`（全体）
class CodexAdapter implements AgentAdapter {
  static const id = 'codex';

  final CodexHistoryReader _historyReader;
  final CodexRolloutReader _rolloutReader;
  final CodexTranscriptExtractor _transcriptExtractor;
  final CodexPathResolver _pathResolver;

  /// 設定での codex パス上書き（空なら自動検出）。
  final String codexPathOverride;

  factory CodexAdapter({
    String? codexHome,
    String codexPathOverride = '',
  }) {
    final home = codexHome ?? '${Platform.environment['HOME'] ?? ''}/.codex';
    return CodexAdapter._(home, codexPathOverride);
  }

  CodexAdapter._(String codexHome, this.codexPathOverride)
      : _historyReader = CodexHistoryReader(
          historyFile: File('$codexHome/history.jsonl'),
          excludeMarker: CodexSummarizer.marker,
        ),
        _rolloutReader = CodexRolloutReader(
          sessionsDir: Directory('$codexHome/sessions'),
        ),
        _transcriptExtractor = CodexTranscriptExtractor(
          rolloutReader: CodexRolloutReader(
            sessionsDir: Directory('$codexHome/sessions'),
          ),
        ),
        _pathResolver = CodexPathResolver();

  @override
  String get agentId => id;

  @override
  String get displayName => 'Codex';

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    final entries = await _historyReader.aggregatedEntries();
    if (entries.isEmpty) {
      return [];
    }
    final rolloutIndex = await _rolloutReader.scan();

    // rollout が消えたセッションは codex resume でも復帰できないため除外する
    final selected = <(CodexHistoryEntry, File)>[];
    for (final entry in entries) {
      final rolloutFile = rolloutIndex[entry.sessionId];
      if (rolloutFile == null) {
        continue;
      }
      selected.add((entry, rolloutFile));
      if (selected.length >= limit) {
        break;
      }
    }

    // cwd 取得はファイルごとに独立した読取なので並列に行う
    return Future.wait(selected.map((pair) async {
      final (entry, rolloutFile) = pair;
      final cwd = await _rolloutReader.readCwd(rolloutFile);
      return RecentSession(
        agentId: id,
        sessionId: entry.sessionId,
        projectPath: cwd ?? '',
        lastPrompt: entry.lastPrompt,
        updatedAt: entry.updatedAt,
      );
    }));
  }

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) {
    final resume = 'codex resume ${shellEscape(sessionId)}';
    if (projectPath.isEmpty) {
      // session_meta が読めなかったセッション。resume 自体はどこからでも効く
      return resume;
    }
    return 'cd ${shellEscape(projectPath)} && $resume';
  }

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async {
    final codexPath =
        await _pathResolver.resolve(override: codexPathOverride);
    if (codexPath == null) {
      throw const SummarizeException(
        'codex command not found: install codex or add it to PATH',
      );
    }
    final summarizer = CodexSummarizer(codexPath: codexPath);
    // cwd が取れなかったセッションでも要約は動かせるようにする
    final workingDirectory = projectPath.isEmpty
        ? (Platform.environment['HOME'] ?? '.')
        : projectPath;

    switch (scope) {
      case SummaryScope.recent:
        final transcript =
            await _transcriptExtractor.extract(sessionId, rallies: rallies);
        if (transcript == null) {
          throw const SummarizeException(
            'no transcript found for the session',
          );
        }
        return summarizer.summarizeTranscript(
          transcript,
          workingDirectory: workingDirectory,
        );
      case SummaryScope.full:
        return summarizer.summarizeFullSession(
          sessionId: sessionId,
          workingDirectory: workingDirectory,
        );
    }
  }
}
