import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// デバッグビルド専用: コピーフィードバックの時間を実行中に調整するための
/// 置き場（設定画面のデバッグセクションから 1ms 単位で変更できる）。
/// メモリのみで永続化しない。リリースビルドでは各ウィジェットの既定値を使う。
class CopyFeedbackTiming {
  CopyFeedbackTiming._();

  /// 円周スイープにかける時間（ms）。
  static final ValueNotifier<int> sweepMs = ValueNotifier(250);

  /// チェックマーク表示を維持する時間（ms）。
  static final ValueNotifier<int> holdMs = ValueNotifier(400);

  /// 円周スイープアニメーションの有効/無効（無効なら即チェック表示）。
  static final ValueNotifier<bool> animationEnabled = ValueNotifier(true);

  /// アニメーションを再生すべきか（リリースビルドでは常に true）。
  static bool get animate => !kDebugMode || animationEnabled.value;

  /// デバッグビルドなら調整値、リリースビルドなら [release] を返す。
  static Duration sweep(Duration release) => kDebugMode
      ? Duration(milliseconds: sweepMs.value)
      : release;

  static Duration hold(Duration release) => kDebugMode
      ? Duration(milliseconds: holdMs.value)
      : release;
}

/// コピー操作のアイコンボタン。成功すると
/// 1. アイコンの円周を緑の線が時計回りに一周し（スイープ）
/// 2. 描き終わるとアイコンが緑のチェックマークに変わり
/// 3. しばらくして元に戻る（スナックバーは出さない）。
///
/// OS の「視差効果を減らす」（reduce motion）が有効なときはスイープを省略して
/// 直ちにチェックマークを出す。
class CopyIconButton extends StatefulWidget {
  /// コピー本体。完了したらフィードバック表示に切り替わる。
  final Future<void> Function() onCopy;

  final String? tooltip;
  final double iconSize;

  /// 一覧行の並びより小さく詰めて置きたい場合（セッション詳細の ID 行等）。
  final bool compact;

  /// 円周スイープにかける時間。
  final Duration sweepDuration;

  /// チェックマーク表示を維持する時間。
  final Duration feedbackDuration;

  const CopyIconButton({
    super.key,
    required this.onCopy,
    this.tooltip,
    this.iconSize = 18,
    this.compact = false,
    this.sweepDuration = const Duration(milliseconds: 250),
    this.feedbackDuration = const Duration(milliseconds: 400),
  });

  @override
  State<CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<CopyIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  var _copied = false;
  Timer? _revertTimer;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: widget.sweepDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _showCheck();
        }
      });
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _handlePressed() async {
    await widget.onCopy();
    if (!mounted) {
      return;
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !CopyFeedbackTiming.animate) {
      _showCheck();
      return;
    }
    _revertTimer?.cancel();
    _sweep.duration = CopyFeedbackTiming.sweep(widget.sweepDuration);
    setState(() => _copied = false);
    _sweep.forward(from: 0);
  }

  void _showCheck() {
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _revertTimer?.cancel();
    _revertTimer = Timer(CopyFeedbackTiming.hold(widget.feedbackDuration), () {
      if (!mounted) {
        return;
      }
      _sweep.reset();
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 円周スイープはアイコンより一回り大きい円で描く
    final arcExtent = widget.iconSize + 8;
    final icon = SizedBox(
      width: arcExtent,
      height: arcExtent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            _copied ? Icons.check : Icons.copy,
            size: widget.iconSize,
            color: _copied ? Colors.green : null,
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sweep,
              // チェック表示中は満円のまま残し、復帰時に一緒に消す
              builder: (context, _) => CustomPaint(
                painter: _SweepArcPainter(
                  progress: _copied
                      ? 1.0
                      : (_sweep.isAnimating ? _sweep.value : 0.0),
                  color: Colors.green,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return IconButton(
      icon: icon,
      iconSize: arcExtent,
      tooltip: widget.tooltip,
      onPressed: _handlePressed,
      padding: widget.compact ? EdgeInsets.zero : null,
      constraints: widget.compact ? const BoxConstraints() : null,
    );
  }
}

/// 12 時位置から時計回りに progress ぶんの円弧を描く。
class _SweepArcPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SweepArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      return;
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = (Offset.zero & size).deflate(paint.strokeWidth / 2);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_SweepArcPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
