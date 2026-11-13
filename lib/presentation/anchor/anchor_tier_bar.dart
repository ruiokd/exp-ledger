/// 刻度条：四档横轴上的「先验 vs 实测」。
///
/// 为什么不在主曲线上加这一层：主曲线画的是五维能力值，而刻度层画的是
/// 「这件事有多重」的判断——两者 y 轴不是一回事，硬叠会让人以为
/// 「重视程度」在推动能力曲线。
///
/// 所以单独一条：空心点 + 虚线误差带 = 你声明的（先验），
/// 实心点 = 实测反算的。一眼看出差几档。
library;

import 'dart:math' as math;

import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:flutter/material.dart';

class AnchorTierBar extends StatelessWidget {
  const AnchorTierBar({
    super.key,
    required this.resolution,
    this.height = 62,
  });

  final WeightResolution resolution;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TierBarPainter(
          resolution: resolution,
          textStyle: const TextStyle(
            fontSize: Tokens.fontMicro,
            color: AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

class _TierBarPainter extends CustomPainter {
  _TierBarPainter({required this.resolution, required this.textStyle});

  final WeightResolution resolution;
  final TextStyle textStyle;

  static const double _padLeft = 10;
  static const double _padRight = 10;
  static const double _labelHeight = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final double plotW = size.width - _padLeft - _padRight;
    if (plotW <= 1) return;
    final double y = size.height - _labelHeight - 10;

    final List<ImpactTier> tiers = ImpactTier.values;
    final double step = plotW / (tiers.length - 1);

    double xOf(ImpactTier t) => _padLeft + step * t.rank;

    // ---- 底线 + 四档刻度 ----
    final Paint axis = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    canvas.drawLine(Offset(_padLeft, y), Offset(_padLeft + plotW, y), axis);

    for (final ImpactTier t in tiers) {
      final double x = xOf(t);
      canvas.drawLine(
        Offset(x, y - 4),
        Offset(x, y + 4),
        axis..color = AppColors.divider,
      );
      _text(canvas, t.label, Offset(x, y + 8), align: TextAlign.center);
    }

    // ---- 先验：空心点 + 虚线误差带 ----
    final ImpactTier? declared = resolution.declaredTier;
    if (declared != null && resolution.priorStillActive) {
      final double cx = xOf(declared);
      final double half = step * 0.45;
      _dashedLine(canvas, Offset(cx - half, y), Offset(cx + half, y),
          AppColors.inkFaint);
      final Paint hollow = Paint()
        ..color = AppColors.inkFaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(Offset(cx, y), 5, hollow);
      _text(canvas, '先验', Offset(cx, y - 20), align: TextAlign.center);
    }

    // ---- 实测：实心点 ----
    final ImpactTier? measured = resolution.measuredTier;
    if (measured != null) {
      final double cx = xOf(measured);
      final Paint solid = Paint()..color = AppColors.accent;
      canvas.drawCircle(Offset(cx, y), 5, solid);
      _text(
        canvas,
        '实测',
        Offset(cx, y - 20),
        align: TextAlign.center,
        color: AppColors.accent,
      );
      if (declared != null && declared != measured) {
        _dashedLine(
          canvas,
          Offset(math.min(xOf(declared), cx), y - 8),
          Offset(math.max(xOf(declared), cx), y - 8),
          AppColors.accent.withOpacity(0.6),
        );
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const double dash = 3;
    const double gap = 3;
    double x = from.dx;
    while (x < to.dx) {
      final double end = math.min(x + dash, to.dx);
      canvas.drawLine(Offset(x, from.dy), Offset(end, from.dy), p);
      x = end + gap;
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    TextAlign align = TextAlign.left,
    Color? color,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: color == null ? textStyle : textStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double dx = align == TextAlign.center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _TierBarPainter old) =>
      old.resolution.declaredTier != resolution.declaredTier ||
      old.resolution.measuredTier != resolution.measuredTier ||
      old.resolution.priorStillActive != resolution.priorStillActive;
}
