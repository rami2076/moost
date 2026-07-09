import 'package:flutter/material.dart';
import 'package:moost_core/moost_core.dart';

import '../../l10n/app_localizations.dart';

/// メモの登録・編集フォーム。
///
/// CRUD は行わず、保存・キャンセル・削除をコールバックで親（RootScreen）に
/// 依頼するだけ（design.md 6.3: 遷移ロジックはルート画面に集約）。
/// 削除確認はダイアログではなくフォーム内のインライン表示
/// （design.md 7 章ハマりどころ 5: ポップオーバーが閉じるため）。
class MemoFormScreen extends StatefulWidget {
  final String projectPath;
  final String sessionId;
  final String initialTitle;
  final String initialTags;
  final String initialBody;
  final bool isEdit;

  final Future<void> Function({
    required String title,
    required List<String> tags,
    required String body,
  }) onSave;
  final VoidCallback onCancel;
  final Future<void> Function()? onDelete;

  const MemoFormScreen({
    super.key,
    required this.projectPath,
    required this.sessionId,
    required this.initialTitle,
    this.initialTags = '',
    this.initialBody = '',
    required this.isEdit,
    required this.onSave,
    required this.onCancel,
    this.onDelete,
  });

  @override
  State<MemoFormScreen> createState() => _MemoFormScreenState();
}

class _MemoFormScreenState extends State<MemoFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _body;
  var _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _tags = TextEditingController(text: widget.initialTags);
    _body = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _body.dispose();
    super.dispose();
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
              Text(
                widget.isEdit ? l10n.memoFormEditTitle : l10n.memoFormNewTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(widget.projectPath, style: theme.textTheme.bodySmall),
              Text(
                l10n.sessionIdLabel(widget.sessionId),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: l10n.fieldTitleLabel,
                  isDense: true,
                ),
                // タイトルは必須（空だと保存が無効になる）ため再描画する
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tags,
                decoration: InputDecoration(
                  labelText: l10n.fieldTagsLabel,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _body,
                  decoration: InputDecoration(
                    labelText: l10n.fieldBodyLabel,
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 12),
              if (_confirmingDelete)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.deleteConfirmMessage,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _confirmingDelete = false),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      onPressed: () => widget.onDelete?.call(),
                      child: Text(l10n.delete),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    if (widget.isEdit)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: l10n.delete,
                        onPressed: () =>
                            setState(() => _confirmingDelete = true),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _title.text.trim().isEmpty ? null : _save,
                      child: Text(l10n.save),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    await widget.onSave(
      title: _title.text.trim(),
      tags: parseTags(_tags.text),
      body: _body.text,
    );
  }
}
