import 'dart:async';

import 'package:flutter/material.dart';

/// コピー操作のアイコンボタン。成功するとアイコンが緑のチェックマークに
/// 変わり、しばらくして元に戻る（スナックバーは出さない）。
///
/// ポップオーバーの狭い画面でメッセージ表示より視線移動が少なく、
/// どのボタンのコピーが成功したかが一目で分かる。
class CopyIconButton extends StatefulWidget {
  /// コピー本体。完了したらチェックマーク表示に切り替わる。
  final Future<void> Function() onCopy;

  final String? tooltip;
  final double iconSize;

  /// 一覧行の並びより小さく詰めて置きたい場合（セッション詳細の ID 行等）。
  final bool compact;

  /// チェックマーク表示を維持する時間。
  final Duration feedbackDuration;

  const CopyIconButton({
    super.key,
    required this.onCopy,
    this.tooltip,
    this.iconSize = 18,
    this.compact = false,
    this.feedbackDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton> {
  var _copied = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    await widget.onCopy();
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _revertTimer?.cancel();
    _revertTimer = Timer(widget.feedbackDuration, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _copied ? Icons.check : Icons.copy,
      size: widget.iconSize,
      color: _copied ? Colors.green : null,
    );
    return IconButton(
      icon: icon,
      tooltip: widget.tooltip,
      onPressed: _handlePressed,
      padding: widget.compact ? EdgeInsets.zero : null,
      constraints: widget.compact ? const BoxConstraints() : null,
    );
  }
}
