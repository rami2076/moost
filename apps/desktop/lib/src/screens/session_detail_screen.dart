import 'package:flutter/material.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';

/// セッション詳細 + 要約実行（design.md 6.1）。
///
/// 要約結果は SummaryCache（アプリ常駐中のみ）に載せ、同じ範囲を開き直したら
/// 再実行しない（ADR-002）。要約は永続化しない — 残したい要点は
/// 「メモを登録」から人がメモ本文へ書き移す。
class SessionDetailScreen extends StatefulWidget {
  final RecentSession session;
  final AgentAdapter adapter;
  final SummaryCache summaryCache;
  final int initialRallies;

  final VoidCallback onBack;
  final VoidCallback onRegisterMemo;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.adapter,
    required this.summaryCache,
    required this.initialRallies,
    required this.onBack,
    required this.onRegisterMemo,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  // 要約範囲の切替は永続化せず、開くたびに「直近」に戻る（design.md 6.6）
  var _scope = SummaryScope.recent;
  late int _rallies = widget.initialRallies;
  var _running = false;
  String? _error;

  String? get _cachedSummary =>
      widget.summaryCache.get(widget.session.sessionId, _scope, _rallies);

  Future<void> _runSummary() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final summary = await widget.adapter.summarize(
        sessionId: widget.session.sessionId,
        projectPath: widget.session.projectPath,
        scope: _scope,
        rallies: _rallies,
      );
      widget.summaryCache
          .put(widget.session.sessionId, _scope, _rallies, summary);
      if (mounted) setState(() {});
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final session = widget.session;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.sessionDetailTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onBack,
                    child: Text(l10n.back),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(session.displayTitle, style: theme.textTheme.bodyMedium),
              Text(session.projectPath, style: theme.textTheme.bodySmall),
              Text(
                l10n.sessionIdLabel(session.sessionId),
                style: theme.textTheme.bodySmall,
              ),
              const Divider(height: 24),

              // 要約範囲の切替
              SegmentedButton<SummaryScope>(
                segments: [
                  ButtonSegment(
                    value: SummaryScope.recent,
                    label: Text(l10n.summaryScopeRecent),
                  ),
                  ButtonSegment(
                    value: SummaryScope.full,
                    label: Text(l10n.summaryScopeFull),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: _running
                    ? null
                    : (s) => setState(() => _scope = s.first),
              ),
              if (_scope == SummaryScope.recent) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(l10n.summaryRalliesLabel,
                        style: theme.textTheme.bodyMedium),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: (_running || _rallies <= 1)
                          ? null
                          : () => setState(() => _rallies--),
                    ),
                    Text('$_rallies', style: theme.textTheme.bodyMedium),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: (_running || _rallies >= 20)
                          ? null
                          : () => setState(() => _rallies++),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_running ? l10n.summaryRunning : l10n.runSummary),
                onPressed: _running ? null : _runSummary,
              ),
              const SizedBox(height: 4),
              Text(l10n.summaryNotice, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),

              Expanded(child: _buildResult(l10n, theme)),

              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: widget.onRegisterMemo,
                    child: Text(l10n.registerMemo),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult(AppLocalizations l10n, ThemeData theme) {
    if (_error != null) {
      return SingleChildScrollView(
        child: Text(
          l10n.summaryFailed(_error!),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }
    final cached = _cachedSummary;
    if (cached == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('${l10n.lastPromptLabel}: ${widget.session.lastPrompt}',
            style: theme.textTheme.bodySmall),
      );
    }
    return SingleChildScrollView(
      child: SelectableText(cached, style: theme.textTheme.bodyMedium),
    );
  }
}
