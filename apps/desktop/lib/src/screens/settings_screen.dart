import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';
import '../mcp/mcp_binary_locator.dart';
import '../mcp/mcp_setup_service.dart';
import '../widgets/copy_icon_button.dart';

/// 設定画面（design.md 6.6）。
///
/// ログイン時自動起動はプラグイン依存（launch_at_startup）のため、
/// このスライスでは扱わない。変更は onChanged で即 SettingsStore に保存する。
/// 終了ボタンはフッターから移動してきたもの（更新ボタンの確認 UI と
/// 幅を取り合わないようにするため）。
class SettingsScreen extends StatefulWidget {
  final SettingsRepository settingsStore;
  final ClaudePathResolver pathResolver;
  final McpSetupService mcpSetupService;
  final McpBinaryLocator mcpBinaryLocator;
  final VoidCallback onBack;

  /// 表示中のアプリバージョン（例: "1.5.0"）。null なら行ごと非表示
  /// （widget テスト等、package_info_plus を解決できない環境向け）。
  final String? appVersion;

  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.pathResolver,
    required this.mcpSetupService,
    required this.mcpBinaryLocator,
    required this.onBack,
    this.appVersion,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings? _settings;
  late final TextEditingController _claudePath;
  String? _detectedPath;

  bool _mcpBinaryExists = false;
  bool _mcpActionRunning = false;
  String? _mcpStatusMessage;
  String? _mcpDebugTestResult;

  /// 連携状態はプロセス起動を伴い遅いため、設定画面本体のロードとは
  /// 切り離して非同期に取得する。null は「確認中」（各行は個別に
  /// ローディング表示になり、画面全体のスピナーはブロックしない）。
  bool? _claudeCodeConnected;
  bool? _codexConnected;
  bool? _claudeDesktopConnected;

  static const _terminals = ['Terminal.app', 'iTerm2'];

  @override
  void initState() {
    super.initState();
    _claudePath = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsStore.load();
    final detected =
        await widget.pathResolver.resolve(override: settings.claudePath);
    final mcpBinaryExists = await widget.mcpBinaryLocator.exists();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _claudePath.text = settings.claudePath;
      _detectedPath = detected;
      _mcpBinaryExists = mcpBinaryExists;
      // 連携状態は下の _loadMcpConnectionStatus() が別途非同期で埋める。
      // ここで null に戻すのは、_load() が再度呼ばれた場合
      // （claudePath 変更時など）に古い状態を出し続けないため。
      _claudeCodeConnected = null;
      _codexConnected = null;
      _claudeDesktopConnected = null;
    });
    if (mcpBinaryExists) {
      unawaited(_loadMcpConnectionStatus());
    }
  }

  /// 連携状態の確認（`claude mcp get` 等の外部プロセス起動を伴う）は、
  /// 画面本体の表示より明らかに遅い。設定画面を開くたびに全体が
  /// ローディングのまま止まって見えるという指摘（Issue #45 フィードバック4）
  /// を受け、本体の setState とは切り離し、3件を並列に取得してから
  /// 各行だけを個別に更新する。
  Future<void> _loadMcpConnectionStatus() async {
    final results = await Future.wait([
      widget.mcpSetupService.isClaudeCodeConnected(),
      widget.mcpSetupService.isCodexConnected(),
      widget.mcpSetupService.isClaudeDesktopConnected(),
    ]);
    if (!mounted) return;
    setState(() {
      _claudeCodeConnected = results[0];
      _codexConnected = results[1];
      _claudeDesktopConnected = results[2];
    });
  }

  /// Claude Code / Codex CLI / Claude Desktop の連携・解除ボタン共通の
  /// 実行ラッパー。バイナリ起動・外部プロセス実行を伴うため、二重押下を
  /// 止め、成功/失敗を同じ場所にテキストで表示する。成功後は登録状態を
  /// 再読込し、ボタンの表示（連携する ⇔ 連携済み+解除）を切り替える。
  Future<void> _runMcpAction(
    String targetLabel,
    Future<void> Function(String binaryPath) action, {
    required String Function(String target) successMessage,
    required String Function(String target, String error) failureMessage,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _mcpActionRunning = true;
      _mcpStatusMessage = l10n.settingMcpActionRunning;
    });
    try {
      await action(widget.mcpBinaryLocator.binaryPath);
      // 設定本体の再読込は不要。連携状態だけを更新する
      await _loadMcpConnectionStatus();
      if (!mounted) return;
      setState(() {
        _mcpActionRunning = false;
        _mcpStatusMessage = successMessage(targetLabel);
      });
    } on McpSetupException catch (e) {
      if (!mounted) return;
      setState(() {
        _mcpActionRunning = false;
        _mcpStatusMessage = failureMessage(targetLabel, e.message);
      });
    }
  }

  Future<void> _testMcpConnection() async {
    // 一般ユーザーには意味が伝わりにくいという指摘を受け、開発者向け
    // デバッグ欄限定の機能にした（Issue #45 フィードバック3）。他の
    // デバッグ項目と同じく l10n は通さない・結果も専用の表示欄に出す
    setState(() {
      _mcpActionRunning = true;
      _mcpDebugTestResult = 'running...';
    });
    bool success;
    try {
      success = await widget.mcpSetupService
          .testConnection(widget.mcpBinaryLocator.binaryPath);
    } on McpSetupException {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _mcpActionRunning = false;
      _mcpDebugTestResult = success ? 'succeeded' : 'failed';
    });
  }

  @override
  void dispose() {
    _claudePath.dispose();
    super.dispose();
  }

  Future<void> _update(Settings next) async {
    setState(() => _settings = next);
    await widget.settingsStore.save(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = _settings;

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
                    child: Text(l10n.settingsTitle,
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: widget.onBack,
                    child: Text(l10n.back),
                  ),
                ],
              ),
              // アップデート実行後に反映されたか一目で分かるよう、
              // スクロールなしで常に見える見出し直下に置く
              if (widget.appVersion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.settingVersion(widget.appVersion!),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const Divider(height: 24),
              if (settings == null)
                const Center(child: CircularProgressIndicator())
              else
                Expanded(
                  child: ListView(
                    children: [
                      // 復帰先ターミナル（クリックで下にリストが開くコンボボックス）
                      Text(l10n.settingTerminal,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      DropdownMenu<String>(
                        initialSelection: settings.terminalApp,
                        requestFocusOnTap: false,
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: [
                          for (final t in _terminals)
                            DropdownMenuEntry(value: t, label: t),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            _update(settings.copyWith(terminalApp: value));
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // 直近セッション表示件数（5〜100、5 刻みのコンボボックス）
                      Text(l10n.settingRecentLimit,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      DropdownMenu<int>(
                        // 手編集された 5 刻み以外の値は最寄りの選択肢へ丸める
                        initialSelection: (settings.recentSessionLimit / 5)
                                .round()
                                .clamp(1, 20) *
                            5,
                        requestFocusOnTap: false,
                        expandedInsets: EdgeInsets.zero,
                        menuHeight: 240,
                        dropdownMenuEntries: [
                          for (var n = 5; n <= 100; n += 5)
                            DropdownMenuEntry(value: n, label: '$n'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            _update(settings.copyWith(
                                recentSessionLimit: value));
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // claude コマンドのパス（要約用。空欄で自動検出）
                      Text(l10n.settingClaudePath,
                          style: theme.textTheme.bodySmall),
                      TextField(
                        controller: _claudePath,
                        decoration: InputDecoration(
                          hintText: l10n.settingClaudePathHint,
                          isDense: true,
                        ),
                        onSubmitted: (value) async {
                          await _update(settings.copyWith(claudePath: value));
                          await _load();
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _detectedPath == null
                            ? l10n.settingClaudePathNotFound
                            : l10n.settingClaudePathDetected(_detectedPath!),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),

                      // コピー成功アニメーション（永続化されるユーザー設定）
                      SwitchListTile(
                        title: Text(l10n.settingCopyAnimation,
                            style: theme.textTheme.bodyMedium),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: settings.copyAnimation,
                        onChanged: (value) {
                          // 実行時キャリアと保存の両方へ反映する
                          CopyFeedbackTiming.animationEnabled.value = value;
                          _update(
                              settings.copyWith(copyAnimation: value));
                        },
                      ),

                      // MCP 連携（Issue #45）: Claude Code / Codex CLI /
                      // Claude Desktop へワンクリックで登録する。バイナリは
                      // 配布ビルド（.app 同梱）にしか存在しないため、
                      // 開発ビルドでは案内文だけを出す
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        l10n.settingMcpSectionTitle,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(l10n.settingMcpSectionDescription,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      if (!_mcpBinaryExists)
                        Text(l10n.settingMcpBinaryMissing,
                            style: theme.textTheme.bodySmall)
                      else ...[
                        _McpTargetRow(
                          label: l10n.settingMcpTargetClaudeCode,
                          connected: _claudeCodeConnected,
                          connectLabel: l10n.settingMcpConnectButton,
                          connectedLabel: l10n.settingMcpConnectedLabel,
                          disconnectLabel: l10n.settingMcpDisconnectButton,
                          enabled: !_mcpActionRunning,
                          onConnect: () => _runMcpAction(
                            l10n.settingMcpTargetClaudeCode,
                            widget.mcpSetupService.registerClaudeCode,
                            successMessage: l10n.settingMcpActionSuccess,
                            failureMessage: l10n.settingMcpActionFailed,
                          ),
                          onDisconnect: () => _runMcpAction(
                            l10n.settingMcpTargetClaudeCode,
                            (_) => widget.mcpSetupService.unregisterClaudeCode(),
                            successMessage: l10n.settingMcpDisconnectSuccess,
                            failureMessage: l10n.settingMcpDisconnectFailed,
                          ),
                        ),
                        _McpTargetRow(
                          label: l10n.settingMcpTargetCodex,
                          connected: _codexConnected,
                          connectLabel: l10n.settingMcpConnectButton,
                          connectedLabel: l10n.settingMcpConnectedLabel,
                          disconnectLabel: l10n.settingMcpDisconnectButton,
                          enabled: !_mcpActionRunning,
                          onConnect: () => _runMcpAction(
                            l10n.settingMcpTargetCodex,
                            widget.mcpSetupService.registerCodex,
                            successMessage: l10n.settingMcpActionSuccess,
                            failureMessage: l10n.settingMcpActionFailed,
                          ),
                          onDisconnect: () => _runMcpAction(
                            l10n.settingMcpTargetCodex,
                            (_) => widget.mcpSetupService.unregisterCodex(),
                            successMessage: l10n.settingMcpDisconnectSuccess,
                            failureMessage: l10n.settingMcpDisconnectFailed,
                          ),
                        ),
                        _McpTargetRow(
                          label: l10n.settingMcpTargetClaudeDesktop,
                          connected: _claudeDesktopConnected,
                          connectLabel: l10n.settingMcpConnectButton,
                          connectedLabel: l10n.settingMcpConnectedLabel,
                          disconnectLabel: l10n.settingMcpDisconnectButton,
                          enabled: !_mcpActionRunning,
                          onConnect: () => _runMcpAction(
                            l10n.settingMcpTargetClaudeDesktop,
                            widget.mcpSetupService.registerClaudeDesktop,
                            successMessage: l10n.settingMcpActionSuccess,
                            failureMessage: l10n.settingMcpActionFailed,
                          ),
                          onDisconnect: () => _runMcpAction(
                            l10n.settingMcpTargetClaudeDesktop,
                            (_) =>
                                widget.mcpSetupService.unregisterClaudeDesktop(),
                            successMessage: l10n.settingMcpDisconnectSuccess,
                            failureMessage: l10n.settingMcpDisconnectFailed,
                          ),
                        ),
                      ],
                      if (_mcpStatusMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(_mcpStatusMessage!,
                            style: theme.textTheme.bodySmall),
                      ],

                      // デバッグビルド限定: コピーフィードバックの時間調整。
                      // 開発者向けツールのため l10n は通さない・永続化しない
                      if (kDebugMode) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        Text('Debug: copy feedback timing',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              CopyFeedbackTiming.animationEnabled,
                          builder: (context, animationEnabled, _) => Row(
                            children: [
                              Expanded(
                                // sweep はアニメーション有効時のみ意味を持つ
                                child: _DebugMsField(
                                  label: 'sweep',
                                  notifier: CopyFeedbackTiming.sweepMs,
                                  enabled: animationEnabled,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _DebugMsField(
                                  label: 'hold',
                                  notifier: CopyFeedbackTiming.holdMs,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // アップデートボタンの「コピーしました」表示時間。
                        // 上の sweep/hold とは独立した別枠（意図的に非連動）
                        _DebugMsField(
                          label: 'update copied',
                          notifier: CopyFeedbackTiming.updateCopiedHoldMs,
                        ),
                        const SizedBox(height: 16),
                        // moost-mcp バイナリの自己診断（旧: 一般ユーザー向け
                        // 「接続テスト」ボタン）。意味が伝わりにくいという
                        // 指摘（Issue #45 フィードバック3）を受け、開発者向け
                        // デバッグ欄限定にした
                        Text('Debug: moost-mcp self-test',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: (_mcpActionRunning || !_mcpBinaryExists)
                                  ? null
                                  : _testMcpConnection,
                              child: const Text('Run'),
                            ),
                            if (_mcpDebugTestResult != null) ...[
                              const SizedBox(width: 8),
                              Text(_mcpDebugTestResult!,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 8),
                      // フッターから移動（更新ボタンの確認 UI と幅を
                      // 取り合わないようにするため）
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.power_settings_new,
                              size: 16),
                          label: Text(l10n.footerQuit),
                          onPressed: () => exit(0),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// デバッグセクション用のミリ秒入力欄（1ms 単位）。
class _DebugMsField extends StatefulWidget {
  final String label;
  final ValueNotifier<int> notifier;
  final bool enabled;

  const _DebugMsField({
    required this.label,
    required this.notifier,
    this.enabled = true,
  });

  @override
  State<_DebugMsField> createState() => _DebugMsFieldState();
}

class _DebugMsFieldState extends State<_DebugMsField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.notifier.value.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: 'ms',
        isDense: true,
      ),
      onChanged: (value) {
        final ms = int.tryParse(value);
        if (ms != null && ms > 0) {
          widget.notifier.value = ms.clamp(1, 60000);
        }
      },
    );
  }
}

/// MCP 連携先 1 件分の行（Issue #45 フィードバック1: ボタンを横並びの
/// [Wrap] ではなく、縦に続くリストにしてほしいという指摘への対応）。
///
/// 未連携なら [connectLabel] のボタンだけ、連携済みなら [connectedLabel]
/// のラベルと [disconnectLabel] の解除ボタンを出す（フィードバック2:
/// 連携済みでも解除できるようにしてほしいという指摘への対応。連携する
/// ボタン自体は連携済みの間は表示しないので、誤って再登録することもない）。
///
/// [connected] が null の間（連携状態を非同期に確認中）は、ボタンの
/// 代わりに小さいスピナーを出す。設定画面本体はこの確認を待たずに
/// 表示されるため、行ごとに個別のローディングになる（フィードバック4:
/// 画面を開くたびに全体がローディングで止まって見える、への対応）。
class _McpTargetRow extends StatelessWidget {
  final String label;
  final bool? connected;
  final String connectLabel;
  final String connectedLabel;
  final String disconnectLabel;
  final bool enabled;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _McpTargetRow({
    required this.label,
    required this.connected,
    required this.connectLabel,
    required this.connectedLabel,
    required this.disconnectLabel,
    required this.enabled,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = this.connected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          if (connected == null)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.outline,
              ),
            )
          else if (connected) ...[
            Text(
              connectedLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: enabled ? onDisconnect : null,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(disconnectLabel),
            ),
          ] else
            OutlinedButton(
              onPressed: enabled ? onConnect : null,
              child: Text(connectLabel),
            ),
        ],
      ),
    );
  }
}
