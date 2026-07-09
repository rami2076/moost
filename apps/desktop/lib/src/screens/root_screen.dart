import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';

/// 「今どの画面か」を表す状態。スタック型ナビゲーションは使わず、
/// この 1 つの状態変数を switch して画面を切り替える（design.md 6.1 / 6.4）。
///
/// フェーズ 2 の最初のスライスでは list のみ実装。
/// newMemo / editMemo / sessionDetail / settings / notes は次スライスで足す。
sealed class MenuScreen {
  const MenuScreen();
}

class ListScreen extends MenuScreen {
  const ListScreen();
}

/// 一覧のタブ。遷移の「戻り先タブ」制御に使う（design.md 6.3）。
enum ListTab { recent, memos }

class RootScreen extends StatefulWidget {
  final AgentAdapter adapter;
  final MemoStore memoStore;
  final SettingsStore settingsStore;

  const RootScreen({
    super.key,
    required this.adapter,
    required this.memoStore,
    required this.settingsStore,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  // 次スライスで newMemo / sessionDetail 等への遷移で書き換わる
  final MenuScreen _screen = const ListScreen();
  ListTab _tab = ListTab.recent;

  late Future<List<RecentSession>> _sessions;
  late Future<List<Memo>> _memos;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 一覧の再読込。開いたとき・タブ切替時・フォームから戻ったときに呼ぶ
  /// （design.md 6.1: 手動リロードは持たない）。
  void _reload() {
    _sessions = _loadSessions();
    _memos = widget.memoStore.load();
  }

  Future<List<RecentSession>> _loadSessions() async {
    final settings = await widget.settingsStore.load();
    return widget.adapter
        .recentSessions(limit: settings.recentSessionLimit);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      ListScreen() => _buildList(context),
    };
  }

  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<ListTab>(
                segments: [
                  ButtonSegment(
                    value: ListTab.recent,
                    label: Text(l10n.tabRecentSessions),
                  ),
                  ButtonSegment(
                    value: ListTab.memos,
                    label: Text(l10n.tabMemos),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selection) {
                  setState(() {
                    _tab = selection.first;
                    _reload();
                  });
                },
              ),
            ),
            Expanded(
              child: switch (_tab) {
                ListTab.recent => _SessionList(
                    sessions: _sessions,
                    onCopyResumeCommand: _copyResumeCommand,
                  ),
                ListTab.memos => _MemoList(
                    memos: _memos,
                    onCopyResumeCommand: _copyResumeCommand,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyResumeCommand({
    required String projectPath,
    required String sessionId,
  }) async {
    final command = widget.adapter.buildResumeCommand(
      projectPath: projectPath,
      sessionId: sessionId,
    );
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.resumeCommandCopied)),
    );
  }
}

class _SessionList extends StatelessWidget {
  final Future<List<RecentSession>> sessions;
  final Future<void> Function({
    required String projectPath,
    required String sessionId,
  }) onCopyResumeCommand;

  const _SessionList({
    required this.sessions,
    required this.onCopyResumeCommand,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<RecentSession>>(
      future: sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(l10n.loadFailed('${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return Center(child: Text(l10n.noSessionsFound));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final session = items[index];
            return ListTile(
              title: Text(
                session.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                session.projectPath,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: l10n.copyResumeCommand,
                onPressed: () => onCopyResumeCommand(
                  projectPath: session.projectPath,
                  sessionId: session.sessionId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MemoList extends StatelessWidget {
  final Future<List<Memo>> memos;
  final Future<void> Function({
    required String projectPath,
    required String sessionId,
  }) onCopyResumeCommand;

  const _MemoList({
    required this.memos,
    required this.onCopyResumeCommand,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Memo>>(
      future: memos,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(l10n.loadFailed('${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return Center(child: Text(l10n.noMemosFound));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final memo = items[index];
            return ListTile(
              title: Text(
                memo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                memo.tags.isEmpty
                    ? memo.projectPath
                    : '${memo.tags.join(', ')} — ${memo.projectPath}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: l10n.copyResumeCommand,
                onPressed: () => onCopyResumeCommand(
                  projectPath: memo.projectPath,
                  sessionId: memo.sessionId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
