import 'dart:io';

import '../../model/recent_session.dart';
import '../../shell_escape.dart';
import '../agent_adapter.dart';
import '../summarize_exception.dart';
import 'ai_title_reader.dart';
import 'claude_path_resolver.dart';
import 'claude_summarizer.dart';
import 'session_history_reader.dart';
import 'transcript_extractor.dart';

/// Claude Code 向けの [AgentAdapter] 実装（第 1 弾で唯一の実装）。
class ClaudeCodeAdapter implements AgentAdapter {
  static const id = 'claude-code';

  final SessionHistoryReader _historyReader;
  final AiTitleReader _aiTitleReader;
  final TranscriptExtractor _transcriptExtractor;
  final ClaudePathResolver _pathResolver;

  /// 設定での claude パス上書き（空なら自動検出）。
  final String claudePathOverride;

  factory ClaudeCodeAdapter({
    String? claudeHome,
    String claudePathOverride = '',
  }) {
    final home =
        claudeHome ?? '${Platform.environment['HOME'] ?? ''}/.claude';
    return ClaudeCodeAdapter._(home, claudePathOverride);
  }

  ClaudeCodeAdapter._(String claudeHome, this.claudePathOverride)
      : _historyReader = SessionHistoryReader(
          historyFile: File('$claudeHome/history.jsonl'),
          agentId: id,
          excludeMarker: ClaudeSummarizer.marker,
        ),
        _aiTitleReader = AiTitleReader(
          projectsDir: Directory('$claudeHome/projects'),
        ),
        _transcriptExtractor = TranscriptExtractor(
          projectsDir: Directory('$claudeHome/projects'),
        ),
        _pathResolver = ClaudePathResolver();

  @override
  String get agentId => id;

  @override
  String get displayName => 'Claude';

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    final sessions = await _historyReader.recentSessions(limit: limit);
    // ai-title 取得はセッションごとに独立したファイル走査なので並列に行う
    return Future.wait(sessions.map((session) async {
      final aiTitle = await _aiTitleReader.latestAiTitle(session.sessionId);
      return session.withAiTitle(aiTitle);
    }));
  }

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) {
    return 'cd ${shellEscape(projectPath)} && '
        'claude --resume ${shellEscape(sessionId)}';
  }

  @override
  String buildNewSessionCommand({required String projectPath}) {
    return 'cd ${shellEscape(projectPath)} && claude';
  }

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async {
    final claudePath =
        await _pathResolver.resolve(override: claudePathOverride);
    if (claudePath == null) {
      throw const SummarizeException(
        'claude command not found: set the path in settings',
      );
    }
    final summarizer = ClaudeSummarizer(claudePath: claudePath);

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
          workingDirectory: projectPath,
        );
      case SummaryScope.full:
        return summarizer.summarizeFullSession(
          sessionId: sessionId,
          workingDirectory: projectPath,
        );
    }
  }
}
