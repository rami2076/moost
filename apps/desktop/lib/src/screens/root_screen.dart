import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';
import '../update/update_checker.dart';
import '../widgets/copy_icon_button.dart';
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

/// 一覧行のサブタイトル右端に出す最終更新日時（ローカル時刻）。
String _formatListUpdatedAt(AppLocalizations l10n, DateTime updatedAt) {
  final local = updatedAt.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return l10n.listUpdatedAt(
    local.month,
    local.day,
    '${pad(local.hour)}:${pad(local.minute)}',
  );
}

class RootScreen extends StatefulWidget {
  final AdapterRegistry registry;
  final MemoStore memoStore;
  final SettingsStore settingsStore;

  /// トレイからウィンドウが再表示された通知。受けたら一覧を再読込する
  /// （design.md 6.1: ポップオーバーを開いたときに自動更新）。
  final ValueListenable<int>? windowShown;

  /// 更新チェック（Issue #12）。null なら通知機能なし。
  final UpdateChecker? updateChecker;

  /// brew 管理下（Caskroom にあり）かの判定。null なら実環境を見る。
  /// テストで差し替えるための注入ポイント。
  final bool Function()? isBrewManaged;

  /// URL を既定ブラウザで開く。null なら `open` コマンドを使う。
  final Future<void> Function(Uri url)? openUrl;

  const RootScreen({
    super.key,
    required this.registry,
    required this.memoStore,
    required this.settingsStore,
    this.windowShown,
    this.updateChecker,
    this.isBrewManaged,
    this.openUrl,
  });

  static bool defaultIsBrewManaged() =>
      Directory('/opt/homebrew/Caskroom/moost').existsSync() ||
      Directory('/usr/local/Caskroom/moost').existsSync();

  static Future<void> defaultOpenUrl(Uri url) async {
    await Process.run('open', [url.toString()]);
  }

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  MenuScreen _screen = const ListScreen();
  ListTab _tab = ListTab.recent;

  /// メモ一覧の行から削除を押されたメモ。null 以外のとき該当行だけを
  /// 確認表示に置き換える（Swift 版と同じ。他の行は動かさない）。
  Memo? _pendingDeleteMemo;

  // 要約のメモリキャッシュはアプリ常駐中ずっと保持する（ADR-002）
  final SummaryCache _summaryCache = SummaryCache();
  final ClaudePathResolver _pathResolver = ClaudePathResolver();
  final TerminalLauncher _terminalLauncher = TerminalLauncher();
  int _summaryRallies = 1;

  late Future<List<RecentSession>> _sessions;
  late Future<List<Memo>> _memos;

  /// 新バージョンの情報（null なら未検出）。フッターに表示する。
  UpdateInfo? _availableUpdate;

  @override
  void initState() {
    super.initState();
    _reload();
    _checkForUpdate();
    widget.windowShown?.addListener(_onWindowShown);
  }

  @override
  void dispose() {
    widget.windowShown?.removeListener(_onWindowShown);
    _updateCopiedRevertTimer?.cancel();
    super.dispose();
  }

  void _onWindowShown() {
    if (!mounted) return;
    setState(_reload);
    _checkForUpdate();
  }

  /// 新バージョンのチェック。失敗は UpdateChecker 側で沈黙する。
  Future<void> _checkForUpdate() async {
    final checker = widget.updateChecker;
    if (checker == null) {
      return;
    }
    final update = await checker.check();
    if (!mounted || update?.version == _availableUpdate?.version) {
      return;
    }
    setState(() => _availableUpdate = update);
  }

  /// 更新ボタンの brew コマンドコピー成功表示（緑チェック）。
  bool _updateCommandCopied = false;
  Timer? _updateCopiedRevertTimer;

  /// コピーのフィードバック表示中は連打で再トリガーされないよう塞ぐ
  /// （CopyIconButton の _busy と同じ考え方）。
  bool _updateButtonBusy = false;

  /// 更新ボタン: brew 導入なら更新コマンドをコピー（成功はアイコンの
  /// 緑チェックで示す）、手動導入ならリリースページを開く（Issue #12）。
  Future<void> _onUpdateTapped(UpdateInfo update) async {
    if (_updateButtonBusy) {
      return;
    }
    final isBrew =
        (widget.isBrewManaged ?? RootScreen.defaultIsBrewManaged)();
    if (isBrew) {
      setState(() => _updateButtonBusy = true);
      await Clipboard.setData(
        const ClipboardData(text: 'brew update && brew upgrade --cask moost'),
      );
      if (!mounted) return;
      setState(() => _updateCommandCopied = true);
      _updateCopiedRevertTimer?.cancel();
      _updateCopiedRevertTimer = Timer(
          CopyFeedbackTiming.hold(const Duration(milliseconds: 400)), () {
        if (mounted) {
          setState(() {
            _updateCommandCopied = false;
            _updateButtonBusy = false;
          });
        }
      });
    } else {
      await (widget.openUrl ?? RootScreen.defaultOpenUrl)(update.releaseUrl);
    }
  }

  /// 一覧の再読込。開いたとき・タブ切替時・フォームから戻ったときに呼ぶ
  /// （design.md 6.1: 手動リロードは持たない）。
  void _reload() {
    _sessions = _loadSessions();
    _memos = widget.memoStore.load();
    // 一覧が変わるタイミングで出しっぱなしの削除確認を引っ込める
    _pendingDeleteMemo = null;
  }

  Future<List<RecentSession>> _loadSessions() async {
    final settings = await widget.settingsStore.load();
    _summaryRallies = settings.summaryRallyCount;
    // 永続化されたアニメーション設定を実行時キャリアへ反映する
    CopyFeedbackTiming.animationEnabled.value = settings.copyAnimation;
    return widget.registry
        .recentSessions(limit: settings.recentSessionLimit);
  }

  /// バッジ表示用のエージェント名。未知の agentId は生の id をそのまま出す。
  String _agentLabel(String agentId) =>
      widget.registry.byId(agentId)?.displayName ?? agentId;

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
    // セッションは registry 経由で取得したものなので adapter は必ず見つかる
    final adapter = widget.registry.byId(session.agentId)!;
    return SessionDetailScreen(
      session: session,
      adapter: adapter,
      agentName: adapter.displayName,
      summaryCache: _summaryCache,
      initialRallies: _summaryRallies,
      onBack: () => _showList(ListTab.recent),
      // セッション詳細からメモ登録へ（一覧を経由しない直接遷移）
      onRegisterMemo: () =>
          setState(() => _screen = NewMemoScreen(session)),
      onOpenTerminal: () => _openInTerminal(
        agent: session.agentId,
        projectPath: session.projectPath,
        sessionId: session.sessionId,
      ),
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
          agent: session.agentId,
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
                    agentLabel: _agentLabel,
                    onCopyResumeCommand: _copyResumeCommand,
                    onOpenInTerminal: _openInTerminal,
                    onTapSession: (session) =>
                        setState(() => _screen = NewMemoScreen(session)),
                    onOpenDetail: (session) => setState(
                        () => _screen = SessionDetailMenuScreen(session)),
                  ),
                ListTab.memos => _MemoList(
                    memos: _memos,
                    agentLabel: _agentLabel,
                    pendingDeleteMemoId: _pendingDeleteMemo?.id,
                    onCopyResumeCommand: _copyResumeCommand,
                    onOpenInTerminal: _openInTerminal,
                    onTapMemo: (memo) =>
                        setState(() => _screen = EditMemoScreen(memo)),
                    onDeleteMemo: (memo) =>
                        setState(() => _pendingDeleteMemo = memo),
                    onCancelDelete: () =>
                        setState(() => _pendingDeleteMemo = null),
                    onConfirmDelete: _deleteMemoConfirmed,
                  ),
              },
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  /// 削除の実行中フラグ。連打や二重発火で delete が並走すると
  /// アトミック書き込み（.tmp → rename）が競合するため直列化する。
  bool _deletingMemo = false;

  Future<void> _deleteMemoConfirmed(Memo memo) async {
    if (_deletingMemo) {
      return;
    }
    _deletingMemo = true;
    try {
      await widget.memoStore.delete(memo.id);
    } finally {
      _deletingMemo = false;
    }
    if (!mounted) {
      return;
    }
    setState(_reload);
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
          if (_availableUpdate != null)
            TextButton.icon(
              icon: Icon(
                _updateCommandCopied ? Icons.check : Icons.arrow_circle_up,
                size: 16,
                color: _updateCommandCopied ? Colors.green : null,
              ),
              label:
                  Text(l10n.updateAvailable('v${_availableUpdate!.version}')),
              // busy 判定は _onUpdateTapped 冒頭で行う（CopyIconButton と同じ
              // 理由: onPressed を null にするとタップが親へ素通りしうる）
              onPressed: () => _onUpdateTapped(_availableUpdate!),
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

  /// agent に対応する adapter を引く。メモは復帰情報を自己完結で持つため、
  /// 対応 adapter を外した後のメモから呼ばれると null になりうる。
  AgentAdapter? _adapterFor(String agent) {
    final adapter = widget.registry.byId(agent);
    if (adapter == null && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.unknownAgent(agent))),
      );
    }
    return adapter;
  }

  /// 復帰コマンドをクリップボードへ。成功のフィードバックは
  /// 呼び出し元の [CopyIconButton] が担う（スナックバーは出さない）。
  Future<void> _copyResumeCommand({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) async {
    final adapter = _adapterFor(agent);
    if (adapter == null) {
      return;
    }
    final command = adapter.buildResumeCommand(
      projectPath: projectPath,
      sessionId: sessionId,
    );
    await Clipboard.setData(ClipboardData(text: command));
  }

  /// 設定のターミナルで復帰コマンドを実行する。
  Future<void> _openInTerminal({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) async {
    final adapter = _adapterFor(agent);
    if (adapter == null) {
      return;
    }
    final command = adapter.buildResumeCommand(
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
  final String Function(String agentId) agentLabel;
  final Future<void> Function({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) onCopyResumeCommand;
  final Future<void> Function({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) onOpenInTerminal;
  final void Function(RecentSession session) onTapSession;
  final void Function(RecentSession session) onOpenDetail;

  const _SessionList({
    required this.sessions,
    required this.agentLabel,
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
            final updatedAtText =
                _formatListUpdatedAt(l10n, session.updatedAt);
            return ListTile(
              onTap: () => onTapSession(session),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      session.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _AgentBadge(agentLabel(session.agentId)),
                ],
              ),
              // 最終利用日時はサブタイトル行の右端（プロジェクトパスと同じ行）
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      session.projectPath,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    updatedAtText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.terminal, size: 18),
                    tooltip: l10n.openInTerminal,
                    onPressed: () => onOpenInTerminal(
                      agent: session.agentId,
                      projectPath: session.projectPath,
                      sessionId: session.sessionId,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.article_outlined, size: 18),
                    tooltip: l10n.sessionDetailTitle,
                    onPressed: () => onOpenDetail(session),
                  ),
                  CopyIconButton(
                    tooltip: l10n.copyResumeCommand,
                    onCopy: () => onCopyResumeCommand(
                      agent: session.agentId,
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
  final String Function(String agentId) agentLabel;
  final Future<void> Function({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) onCopyResumeCommand;
  final Future<void> Function({
    required String agent,
    required String projectPath,
    required String sessionId,
  }) onOpenInTerminal;
  final void Function(Memo memo) onTapMemo;
  final void Function(Memo memo) onDeleteMemo;

  /// 削除確認中のメモ id。該当行だけ確認表示に置き換える。
  final String? pendingDeleteMemoId;
  final VoidCallback onCancelDelete;
  final void Function(Memo memo) onConfirmDelete;

  const _MemoList({
    required this.memos,
    required this.agentLabel,
    required this.pendingDeleteMemoId,
    required this.onCopyResumeCommand,
    required this.onOpenInTerminal,
    required this.onTapMemo,
    required this.onDeleteMemo,
    required this.onCancelDelete,
    required this.onConfirmDelete,
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
            if (memo.id == pendingDeleteMemoId) {
              return _buildConfirmRow(context, l10n, memo);
            }
            return ListTile(
              onTap: () => onTapMemo(memo),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      memo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _AgentBadge(agentLabel(memo.agent)),
                ],
              ),
              // 最終更新日時はサブタイトル行の右端（セッション一覧と同じ配置）
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      memo.tags.isEmpty
                          ? memo.projectPath
                          : '${memo.tags.join(', ')} — ${memo.projectPath}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatListUpdatedAt(l10n, memo.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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
                      agent: memo.agent,
                      projectPath: memo.projectPath,
                      sessionId: memo.sessionId,
                    ),
                  ),
                  CopyIconButton(
                    tooltip: l10n.copyResumeCommand,
                    onCopy: () => onCopyResumeCommand(
                      agent: memo.agent,
                      projectPath: memo.projectPath,
                      sessionId: memo.sessionId,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: l10n.delete,
                    onPressed: () => onDeleteMemo(memo),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 削除確認中の行。通常行と同じ 2 行分の高さを保ったまま、
  /// 内容だけを「削除しますか？ + キャンセル / 削除」に置き換える。
  Widget _buildConfirmRow(
    BuildContext context,
    AppLocalizations l10n,
    Memo memo,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    // 行内に収める小ぶりなボタン（通常サイズだと行の主役になりすぎる）
    final compactStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 28),
      textStyle: const TextStyle(fontSize: 12),
    );
    return ListTile(
      title: Text(
        l10n.deleteConfirmTitled(memo.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // 通常行（タイトル + サブタイトル）と高さを揃えるための空行
      subtitle: const Text(''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonal(
            style: compactStyle,
            onPressed: onCancelDelete,
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: compactStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(colorScheme.error),
              foregroundColor: WidgetStatePropertyAll(colorScheme.onError),
            ),
            onPressed: () => onConfirmDelete(memo),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

/// 統合リストでどのエージェントのセッション/メモかを示す小さなバッジ。
class _AgentBadge extends StatelessWidget {
  final String label;

  const _AgentBadge(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
