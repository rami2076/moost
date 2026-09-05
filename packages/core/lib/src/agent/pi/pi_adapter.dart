import '../../model/recent_session.dart';
import '../../shell_escape.dart';
import '../agent_adapter.dart';
import '../summarize_exception.dart';
import 'pi_session_history_reader.dart';
import 'pi_transcript_extractor.dart';

/// pi（この coding agent）向けの [AgentAdapter] 実装。
///
/// pi のセッションは `~/.pi/agent/sessions/<cwd毎>/<ts>_<id>.jsonl` に保存。
/// 復帰コマンドは `pi --session <id>`。
///
/// 要約は pi のヘッドレス実行ではなくローカル抽出とする
/// （pi には claude -p / codex exec 相当の安価な要約コマンドがないため、
/// API 消費なしで末尾のやり取りを返す）。
class PiAdapter implements AgentAdapter {
  static const id = 'pi';

  /// 起動時に指定する provider 名（空なら付けない）。
  final String provider;

  /// 起動時に指定する model 名（空なら付けない）。
  final String model;

  final PiSessionHistoryReader _historyReader;
  final PiTranscriptExtractor _transcriptExtractor;

  PiAdapter({
    this.provider = '',
    this.model = '',
    PiSessionHistoryReader? historyReader,
    PiTranscriptExtractor? transcriptExtractor,
  })  : _historyReader = historyReader ?? PiSessionHistoryReader(),
        _transcriptExtractor =
            transcriptExtractor ?? PiTranscriptExtractor();

  @override
  String get agentId => id;

  @override
  String get displayName => 'pi';

  @override
  Future<List<RecentSession>> recentSessions({int limit = 20}) async {
    final entries = await _historyReader.recentSessions(limit: limit);
    return [
      for (final e in entries)
        RecentSession(
          agentId: id,
          sessionId: e.sessionId,
          projectPath: e.projectPath,
          lastPrompt: e.lastPrompt,
          updatedAt: e.updatedAt,
        ),
    ];
  }

  @override
  String buildResumeCommand({
    required String projectPath,
    required String sessionId,
  }) {
    return _build('pi --session ${shellEscape(sessionId)}', projectPath);
  }

  @override
  String buildNewSessionCommand({required String projectPath}) {
    return _build('pi', projectPath);
  }

  /// `prefix`（例: `pi --session <id>`）にプロジェクト cd と
  /// provider / model 指定を連結する。
  String _build(String prefix, String projectPath) {
    final flags = [
      if (provider.isNotEmpty) '--provider ${shellEscape(provider)}',
      if (model.isNotEmpty) '--model ${shellEscape(model)}',
    ].join(' ');
    final command = flags.isEmpty ? prefix : '$prefix $flags';
    if (projectPath.isEmpty) {
      return command;
    }
    return 'cd ${shellEscape(projectPath)} && $command';
  }

  @override
  Future<String> summarize({
    required String sessionId,
    required String projectPath,
    required SummaryScope scope,
    int rallies = 1,
  }) async {
    final text = await _transcriptExtractor.extract(
      sessionId: sessionId,
      full: scope == SummaryScope.full,
      rallies: rallies,
    );
    if (text.isEmpty) {
      throw const SummarizeException('no transcript found for the session');
    }
    return text;
  }
}
