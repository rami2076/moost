import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 注意画面（design.md 6.1）。利用枠消費・権限・保持期間・更新タイミングを説明する。
class NotesScreen extends StatelessWidget {
  final VoidCallback onBack;

  const NotesScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget note(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        );

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
                    child: Text(l10n.notesTitle,
                        style: theme.textTheme.titleMedium),
                  ),
                  TextButton(onPressed: onBack, child: Text(l10n.back)),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    note(l10n.noteAutomationTitle, l10n.noteAutomationBody),
                    note(l10n.noteRetentionTitle, l10n.noteRetentionBody),
                    note(l10n.noteSummaryTitle, l10n.noteSummaryBody),
                    note(l10n.noteRefreshTitle, l10n.noteRefreshBody),
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
