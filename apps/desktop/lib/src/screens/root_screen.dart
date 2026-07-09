import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';
import 'memo_form_screen.dart';
import 'notes_screen.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';

/// 「今どの画面か」を表す状態。スタック型ナビゲーションは使わず、
/// この 1 つの状態変数を switch して画面を切り替える（design.md 6.1 / 6.4）。
sealed class MenuScreen {
  const MenuScreen();
}

class ListScreen extends MenuScreen {
  const ListScreen();
}

class NewMemoScreen extends MenuScreen {
  final RecentSession session;

  const NewMemoScreen(this.session);
}

class EditMemoScreen extends MenuScreen {
  final Memo memo;

  const EditMemoScreen(this.memo);
}

class SessionDetailMenuScreen extends MenuScreen {
  final RecentSession session;

  const SessionDetailMenuScreen(this.session);
}

class SettingsMenuScreen extends MenuScreen {
  const SettingsMenuScreen();
}

class NotesMenuScreen extends MenuScreen {
  const NotesMenuScreen();
}

/// 一覧のタブ。遷移の「戻り先タブ」制御に使う（design.md 6.3）。
enum ListTab { recent, memos }

class RootScreen extends StatefulWidget {
  final AgentAdapter adapter;
  final MemoStore memoStore;
  final SettingsStore settingsStore;

  /// トレイからウィンドウが再表示された通知。受けたら一覧を再読込する
  /// （design.md 6.1: ポップオーバーを開いたときに自動更新）。
  final ValueListenable<int>? windowShown;

  const RootScreen({
    super.key,
    required this.adapter,
    required this.memoStore,
    required this.settingsStore,
    this.windowShown,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  MenuScreen _screen = const ListScreen();
  ListTab _tab = ListTab.recent;

  // 要約のメモリキャッシュはアプリ常駐中ずっと保持する（ADR-002）
  final SummaryCache _summaryCache = SummaryCache();
  final ClaudePathResolver _pathResolver = ClaudePathResolver();
  final TerminalLauncher _terminalLauncher = TerminalLauncher();
  int _summaryRallies = 1;

  late Future<List<RecentSession>> _sessions;
  late Future<List<Memo>> _memos;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.windowShown?.addListener(_onWindowShown);
  }

  @override
  void dispose() {
    widget.windowShown?.removeListener(_onWindowShown);
    super.dispose();
  }

  void _onWindowShown() {
    if (!mounted) return;
    setState(_reload);
  }

  /// 一覧の再読込。開いたとき・タブ切替時・フォームから戻ったときに呼ぶ
  /// （design.md 6.1: 手動リロードは持たない）。
  void _reload() {
    _sessions = _loadSessions();
    _memos = widget.memoStore.load();
  }

  Future<List<RecentSession>> _loadSessions() async {
    final settings = await widget.settingsStore.load();
    _summaryRallies = settings.summaryRallyCount;
    return widget.adapter
        .recentSessions(limit: settings.recentSessionLimit);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_screen) {
      ListScreen() => _buildList(context),
      NewMemoScreen(:final session) => _buildNewMemo(session),
      EditMemoScreen(:final memo) => _buildEditMemo(memo),
      SessionDetailMenuScreen(:final session) => _buildSessionDetail(session),
      SettingsMenuScreen() => SettingsScreen(
          settingsStore: widget.settingsStore,
          pathResolver: _pathResolver,
          onBack: () => _showList(_tab),
        ),
      NotesMenuScreen() => NotesScreen(onBack: () => _showList(_tab)),
    };
  }

  Widget _buildSessionDetail(RecentSession session) {
    return SessionDetailScreen(
      session: session,
      adapter: widget.adapter,
      summaryCache: _summaryCache,
      initialRallies: _summaryRallies,
      onBack: () => _showList(ListTab.recent),
      // セッション詳細からメモ登録へ（一覧を経由しない直接遷移）
      onRegisterMemo: () =>
          setState(() => _screen = NewMemoScreen(session)),
    );
  }

  /// 遷移は「戻り先のタブ」まで制御する（design.md 6.3）。
  void _showList(ListTab tab) {
    setState(() {
      _screen = const ListScreen();
      _tab = tab;
      _reload();
    });
  }

  Widget _buildNewMemo(RecentSession session) {
    return MemoFormScreen(
      projectPath: session.projectPath,
      sessionId: session.sessionId,
      // メモタイトルの初期値はセッションタイトル（requirements.md 3.3）
      initialTitle: session.displayTitle,
      isEdit: false,
      onSave: ({required title, required tags, required body}) async {
        final now = DateTime.now().toUtc();
        await widget.memoStore.add(Memo(
          id: generateUuidV4(),
          agent: widget.adapter.agentId,
          sessionId: session.sessionId,
          title: title,
          tags: tags,
          body: body,
          projectPath: session.projectPath,
          createdAt: now,
          updatedAt: now,
        ));
        // 登録したメモを確認できるようメモ一覧タブへ戻す
        _showList(ListTab.memos);
      },
      // 入口だった直近セッションタブへ戻す
      onCancel: () => _showList(ListTab.recent),
    );
  }

  Widget _buildEditMemo(Memo memo) {
    return MemoFormScreen(
      projectPath: memo.projectPath,
      sessionId: memo.sessionId,
      initialTitle: memo.title,
      initialTags: memo.tags.join(', '),
      initialBody: memo.body,
      isEdit: true,
      onSave: ({required title, required tags, required body}) async {
        await widget.memoStore
            .update(memo.id, title: title, tags: tags, body: body);
        _showList(ListTab.memos);
      },
      onCancel: () => _showList(ListTab.memos),
      onDelete: () async {
        await widget.memoStore.delete(memo.id);
        _showList(ListTab.memos);
      },
    );
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
                    onOpenInTerminal: _openInTerminal,
                    onTapSession: (session) =>
                        setState(() => _screen = NewMemoScreen(session)),
                    onOpenDetail: (session) => setState(
                        () => _screen = SessionDetailMenuScreen(session)),
                  ),
                ListTab.memos => _MemoList(
                    memos: _memos,
                    onCopyResumeCommand: _copyResumeCommand,
                    onOpenInTerminal: _openInTerminal,
                    onTapMemo: (memo) =>
                        setState(() => _screen = EditMemoScreen(memo)),
                  ),
              },
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.settings, size: 16),
            label: Text(l10n.footerSettings),
            onPressed: () =>
                setState(() => _screen = const SettingsMenuScreen()),
          ),
          TextButton.icon(
            icon: const Icon(Icons.info_outline, size: 16),
            label: Text(l10n.footerNotes),
            onPressed: () =>
                setState(() => _screen = const NotesMenuScreen()),
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.power_settings_new, size: 16),
            label: Text(l10n.footerQuit),
            onPressed: () => exit(0),
          ),
        ],
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

  /// 設定のターミナルで復帰コマンドを実行する。
  Future<void> _openInTerminal({
    required String projectPath,
    required String sessionId,
  }) async {
    final command = widget.adapter.buildResumeCommand(
      projectPath: projectPath,
      sessionId: sessionId,
    );
    final l10n = AppLocalizations.of(context)!;
    try {
      final settings = await widget.settingsStore.load();
      await _terminalLauncher.launch(
        terminal: TerminalApp.fromSetting(settings.terminalApp),
        command: command,
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.terminalLaunchFailed('$e'))),
      );
    }
  }
}

class _SessionList extends StatelessWidget {
  final Future<List<RecentSession>> sessions;
  final Future<void> Function({
    required String projectPath,
    required String sessionId,
  }) onCopyResumeCommand;
  final Future<void> Function({
    required String projectPath,
    required String sessionId,
  }) onOpenInTerminal;
  final void Function(RecentSession session) onTapSession;
  final void Function(RecentSession session) onOpenDetail;

  const _SessionList({
    required this.sessions,
    required this.onCopyResumeCommand,
    required this.onOpenInTerminal,
    required this.onTapSession,
    required this.onOpenDetail,
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
              onTap: () => onTapSession(session),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.terminal, size: 18),
                    tooltip: l10n.openInTerminal,
                    onPressed: () => onOpenInTerminal(
                      projectPath: session.projectPath,
                      sessionId: session.sessionId,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.article_outlined, size: 18),
                    tooltip: l10n.sessionDetailTitle,
                    onPressed: () => onOpenDetail(session),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l10n.copyResumeCommand,
                    onPressed: () => onCopyResumeCommand(
                      projectPath: session.projectPath,
                      sessionId: session.sessionId,
                    ),
                  ),
                ],
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
  final Future<void> Function({
    required String projectPath,
    required String sessionId,
  }) onOpenInTerminal;
  final void Function(Memo memo) onTapMemo;

  const _MemoList({
    required this.memos,
    required this.onCopyResumeCommand,
    required this.onOpenInTerminal,
    required this.onTapMemo,
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
              onTap: () => onTapMemo(memo),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // メモは復帰情報を自己完結で持つので、元セッションが一覧から
                  // 消えていてもここから再開できる（ADR-003）
                  IconButton(
                    icon: const Icon(Icons.terminal, size: 18),
                    tooltip: l10n.resumeInTerminal,
                    onPressed: () => onOpenInTerminal(
                      projectPath: memo.projectPath,
                      sessionId: memo.sessionId,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l10n.copyResumeCommand,
                    onPressed: () => onCopyResumeCommand(
                      projectPath: memo.projectPath,
                      sessionId: memo.sessionId,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
