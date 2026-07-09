import 'package:flutter/material.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';

/// 設定画面（design.md 6.6）。
///
/// ログイン時自動起動とバージョン表示はプラグイン依存（launch_at_startup /
/// package_info_plus）のため、このスライスでは扱わない。
/// 変更は onChanged で即 SettingsStore に保存する。
class SettingsScreen extends StatefulWidget {
  final SettingsStore settingsStore;
  final ClaudePathResolver pathResolver;
  final VoidCallback onBack;

  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.pathResolver,
    required this.onBack,
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
              const Divider(height: 24),
              if (settings == null)
                const Center(child: CircularProgressIndicator())
              else
                Expanded(
                  child: ListView(
                    children: [
                      // 復帰先ターミナル
                      Text(l10n.settingTerminal,
                          style: theme.textTheme.bodySmall),
                      DropdownButton<String>(
                        value: settings.terminalApp,
                        isExpanded: true,
                        items: [
                          for (final t in _terminals)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _update(settings.copyWith(terminalApp: value));
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // 直近セッション表示件数（5〜100、5 刻み）
                      Text(l10n.settingRecentLimit,
                          style: theme.textTheme.bodySmall),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: settings.recentSessionLimit <= 5
                                ? null
                                : () => _update(settings.copyWith(
                                    recentSessionLimit:
                                        settings.recentSessionLimit - 5)),
                          ),
                          Text('${settings.recentSessionLimit}',
                              style: theme.textTheme.bodyMedium),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: settings.recentSessionLimit >= 100
                                ? null
                                : () => _update(settings.copyWith(
                                    recentSessionLimit:
                                        settings.recentSessionLimit + 5)),
                          ),
                        ],
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
