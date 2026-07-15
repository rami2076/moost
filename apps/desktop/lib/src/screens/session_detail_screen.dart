import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';

/// セッション詳細 + 要約実行（design.md 6.1。レイアウトは Swift 版に合わせる）。
///
/// - メタ情報はラベル + 値の表形式（セッション ID はコピー付き）
/// - 範囲セグメントと「直近 N ラリーを対象」ステッパーは同一行
/// - 下部バー: 左に「ターミナルで開く」「メモを登録」、右端に「戻る」
/// - 要約結果は SummaryCache（アプリ常駐中のみ）に載せる（ADR-002）
class SessionDetailScreen extends StatefulWidget {
  final RecentSession session;
  final AgentAdapter adapter;

  /// メタ情報と要約ボタンに出すエージェント名（例: "Claude"）。
  final String agentName;

  final SummaryCache summaryCache;
  final int initialRallies;

  final VoidCallback onBack;
  final VoidCallback onRegisterMemo;
  final VoidCallback onOpenTerminal;

  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.adapter,
    required this.agentName,
    required this.summaryCache,
    required this.initialRallies,
    required this.onBack,
    required this.onRegisterMemo,
    required this.onOpenTerminal,
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

  Future<void> _copySessionId() async {
    await Clipboard.setData(
        ClipboardData(text: widget.session.sessionId));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.sessionDetailTitle,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildMetadata(l10n, theme),
              const Divider(height: 24),
              _buildSummaryControls(l10n, theme),
              const SizedBox(height: 12),
              Expanded(child: _buildResult(l10n, theme)),
              const SizedBox(height: 8),
              _buildBottomBar(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadata(AppLocalizations l10n, ThemeData theme) {
    final session = widget.session;

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
              Expanded(child: value),
            ],
          ),
        );

    Widget text(String value) => Text(
          value,
          style: theme.textTheme.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

    final lastUsed = session.updatedAt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    final lastUsedText = '${lastUsed.year}-${pad(lastUsed.month)}-'
        '${pad(lastUsed.day)} ${pad(lastUsed.hour)}:${pad(lastUsed.minute)}';

    return Column(
      children: [
        row(l10n.metaTitle, text(session.displayTitle)),
        row(l10n.metaAgent, text(widget.agentName)),
        row(l10n.metaProject, text(session.projectPath)),
        row(
          l10n.metaSessionId,
          Row(
            children: [
              Flexible(child: text(session.sessionId)),
              const SizedBox(width: 4),
              InkWell(
                onTap: _copySessionId,
                child: const Icon(Icons.copy, size: 14),
              ),
            ],
          ),
        ),
        row(l10n.metaLastUsed, text(lastUsedText)),
        row(l10n.lastPromptLabel, text(session.lastPrompt)),
      ],
    );
  }

  Widget _buildSummaryControls(AppLocalizations l10n, ThemeData theme) {
    final recentSelected = _scope == SummaryScope.recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 範囲セグメント + 「直近 N ラリーを対象」ステッパー（同一行）
        Row(
          children: [
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
              showSelectedIcon: false,
              onSelectionChanged: _running
                  ? null
                  : (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.ralliesTarget(_rallies),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: recentSelected ? null : theme.disabledColor,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: (!recentSelected || _running || _rallies >= 20)
                      ? null
                      : () => setState(() => _rallies++),
                  child: const Icon(Icons.arrow_drop_up, size: 20),
                ),
                InkWell(
                  onTap: (!recentSelected || _running || _rallies <= 1)
                      ? null
                      : () => setState(() => _rallies--),
                  child: const Icon(Icons.arrow_drop_down, size: 20),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 要約実行ボタン + 注記（同一行）
        Row(
          children: [
            FilledButton.tonalIcon(
              icon: _running
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_running
                  ? l10n.summaryRunning
                  : l10n.runSummary(widget.agentName)),
              onPressed: _running ? null : _runSummary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.summaryNotice,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ],
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
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: SelectableText(cached, style: theme.textTheme.bodyMedium),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Row(
      children: [
        FilledButton.tonalIcon(
          icon: const Icon(Icons.terminal, size: 16),
          label: Text(l10n.openInTerminal),
          onPressed: widget.onOpenTerminal,
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: widget.onRegisterMemo,
          child: Text(l10n.registerMemo),
        ),
        const Spacer(),
        TextButton(
          onPressed: widget.onBack,
          child: Text(l10n.back),
        ),
      ],
    );
  }
}
