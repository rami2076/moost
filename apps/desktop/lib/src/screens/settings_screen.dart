import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/copy_icon_button.dart';

/// 設定画面（design.md 6.6）。
///
/// ログイン時自動起動はプラグイン依存（launch_at_startup）のため、
/// このスライスでは扱わない。変更は onChanged で即 SettingsStore に保存する。
/// 終了ボタンはフッターから移動してきたもの（更新ボタンの確認 UI と
/// 幅を取り合わないようにするため）。
class SettingsScreen extends StatefulWidget {
  final SettingsStore settingsStore;
  final ClaudePathResolver pathResolver;
  final VoidCallback onBack;

  /// 表示中のアプリバージョン（例: "1.5.0"）。null なら行ごと非表示
  /// （widget テスト等、package_info_plus を解決できない環境向け）。
  final String? appVersion;

  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.pathResolver,
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
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _claudePath.text = settings.claudePath;
      _detectedPath = detected;
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
