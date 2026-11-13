import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:flutter/material.dart';

/// 曲线的数据模型。
///
/// 历史与预测分两段存：区间不同、颜色不同、可信度也不同，
/// 混在一个列表里迟早会把"发生过"和"猜的"画成一条线。
class ChartModel {
  const ChartModel({
    required this.days,
    required this.values,
    required this.forecastDays,
    required this.maintain,
    required this.correct,
    required this.low,
    required this.high,
    required this.riskDays,
    required this.interruptionDays,
    required this.today,
    required this.minY,
    required this.maxY,
  });

  /// 历史日期（升序），与 [values] 一一对应。
  final List<DayKey> days;
  final List<double> values;

  /// 预测日期（不含今天那一格）。
  final List<DayKey> forecastDays;
  final List<double> maintain;
  final List<double> correct;
  final List<double> low;
  final List<double> high;

  /// 负荷爬升过陡的日子（ACWR 警戒/高风险）。
  final Set<DayKey> riskDays;

  /// 中断期（生病/受伤/加班/旅行）：图上换底色，不算懈怠。
  final Set<DayKey> interruptionDays;

  final DayKey today;
  final double minY;
  final double maxY;

  bool get hasForecast => forecastDays.isNotEmpty;

  /// x 轴按**真实日期**排布，不是按点序号。
  /// 按序号排会把"每 3 天一格"的预测画得和每天一格一样长，看起来像 30 天。
  DayKey get axisStart => days.isEmpty ? today : days.first;

  DayKey get axisEnd =>
      forecastDays.isNotEmpty ? forecastDays.last : (days.isEmpty ? today : days.last);

  int get axisSpanDays => axisEnd.diffDays(axisStart);
}

/// 四层叠加的主图。
///
/// 底下两层是**背景信息**（中断期底色、风险区底色），
/// 上面两层是**判断**（置信带、两条未来线）。
/// 顺序不能反：底色被曲线压住，才看得出"这段时间发生了什么"。
class SettlementChartPainter extends CustomPainter {
  SettlementChartPainter({
    required this.model,
    required this.historyColor,
    required this.correctColor,
    required this.maintainColor,
  });

  final ChartModel model;
  final Color historyColor;
  final Color correctColor;
  final Color maintainColor;

  static const double _left = 36;
  static const double _right = 10;
  static const double _top = 16;
  static const double _bottom = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final double plotW = size.width - _left - _right;
    final double plotH = size.height - _top - _bottom;
    if (plotW <= 1 || plotH <= 1 || model.days.isEmpty) return;

    final Rect plot = Rect.fromLTWH(_left, _top, plotW, plotH);
    final int span = model.axisSpanDays <= 0 ? 1 : model.axisSpanDays;

    double xFor(DayKey day) =>
        _left + plotW * (day.diffDays(model.axisStart) / span);

    double yAt(double v) {
      final double range = model.maxY - model.minY;
      final double t = range <= 0.0001 ? 0.5 : (v - model.minY) / range;
      return _top + plotH * (1 - t.clamp(0.0, 1.0));
    }

    double slotWidth() => math.max(1.0, plotW / span);

    // ---- 第 1 层：中断期底色 ----
    final Paint interruptionPaint =
        Paint()..color = AppColors.neutralSoft.withOpacity(0.8);
    for (final DayKey day in model.interruptionDays) {
      _fillDay(canvas, plot, xFor(day), slotWidth(), interruptionPaint);
    }

    // ---- 第 2 层：风险区底色 ----
    final Paint riskPaint = Paint()..color = AppColors.negativeSoft;
    for (final DayKey day in model.riskDays) {
      _fillDay(canvas, plot, xFor(day), slotWidth(), riskPaint);
    }

    // ---- 网格与刻度 ----
    _paintGrid(canvas, plot, yAt);

    final DayKey today = model.days.last;
    final double anchorValue = model.values.isEmpty ? 0 : model.values.last;
    final double todayX = xFor(today);

    // ---- 第 3 层：置信带 ----
    if (model.hasForecast) {
      final Path band = Path();
      band.moveTo(todayX, yAt(model.high.first));
      for (var i = 1; i < model.high.length; i++) {
        band.lineTo(xFor(model.forecastDays[i]), yAt(model.high[i]));
      }
      for (var i = model.low.length - 1; i >= 0; i--) {
        band.lineTo(xFor(model.forecastDays[i]), yAt(model.low[i]));
      }
      band.close();
      canvas.drawPath(
        band,
        Paint()..color = AppColors.calm.withOpacity(0.14),
      );

      // ---- 修正增益带：立即修正与维持现状之间的差 ----
      final Path gain = Path();
      gain.moveTo(todayX, yAt(anchorValue));
      for (var i = 0; i < model.correct.length; i++) {
        gain.lineTo(xFor(model.forecastDays[i]), yAt(model.correct[i]));
      }
      for (var i = model.maintain.length - 1; i >= 0; i--) {
        gain.lineTo(xFor(model.forecastDays[i]), yAt(model.maintain[i]));
      }
      gain.close();
      canvas.drawPath(
        gain,
        Paint()..color = AppColors.accent.withOpacity(0.10),
      );
    }

    // ---- 第 4 层：曲线 ----
    if (model.values.length >= 2) {
      final Path history = Path()
        ..moveTo(xFor(model.days.first), yAt(model.values.first));
      for (var i = 1; i < model.values.length; i++) {
        history.lineTo(xFor(model.days[i]), yAt(model.values[i]));
      }
      canvas.drawPath(
        history,
        Paint()
          ..color = historyColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawCircle(
        Offset(xFor(model.days.first), yAt(model.values.first)),
        3,
        Paint()..color = historyColor,
      );
    }

    if (model.hasForecast) {
      // 维持现状：虚线。虚线本身就在说"这是估计"。
      final Path maintainPath = Path()..moveTo(todayX, yAt(anchorValue));
      for (var i = 0; i < model.maintain.length; i++) {
        maintainPath.lineTo(
          xFor(model.forecastDays[i]),
          yAt(model.maintain[i]),
        );
      }
      _drawDashed(
        canvas,
        maintainPath,
        Paint()
          ..color = maintainColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final Path correctPath = Path()..moveTo(todayX, yAt(anchorValue));
      for (var i = 0; i < model.correct.length; i++) {
        correctPath.lineTo(
          xFor(model.forecastDays[i]),
          yAt(model.correct[i]),
        );
      }
      canvas.drawPath(
        correctPath,
        Paint()
          ..color = correctColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // ---- 今天分界 ----
    _drawDashed(
      canvas,
      Path()
        ..moveTo(todayX, _top)
        ..lineTo(todayX, _top + plotH),
      Paint()
        ..color = AppColors.inkFaint.withOpacity(0.55)
        ..strokeWidth = 1,
      dash: 3,
      gap: 4,
    );
    _paintText(
      canvas,
      '今天',
      Offset(todayX + 4, _top - 2),
      const TextStyle(fontSize: Tokens.fontMicro, color: AppColors.inkFaint),
    );

    // ---- x 轴日期 ----
    // 防重叠：首尾优先占用，中间那格只有真挤得下才画。
    // 之前是硬画三个标签（first / mid / last），数据点稀疏时 mid 会贴在 first 上，
    // 显示成「11/1011/13」这种糊在一起的字符串。
    _paintAxisLabels(canvas, plot, plotW, plotH, xFor);
  }

  /// x 轴日期：首尾一定画，中间那格按剩余空间决定画不画。
  ///
  /// 三条规矩：
  ///   1. 左端左对齐、右端右对齐，避免标签跑出绘图区；
  ///   2. 任何两个标签之间至少留 [_axisLabelGap] 像素；
  ///   3. 首尾是同一天（数据只有一格）时只画一个，不叠字。
  void _paintAxisLabels(
    Canvas canvas,
    Rect plot,
    double plotW,
    double plotH,
    double Function(DayKey day) xFor,
  ) {
    if (model.days.isEmpty) return;
    final double y = _top + plotH + 6;
    const TextStyle style =
        TextStyle(fontSize: Tokens.fontMicro, color: AppColors.inkFaint);

    double measure(String text) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    void paintAt(String text, double left) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left, y));
    }

    final String firstLabel = model.days.first.shortLabel;
    final String lastLabel = model.hasForecast
        ? model.forecastDays.last.shortLabel
        : model.days.last.shortLabel;

    if (firstLabel == lastLabel) {
      paintAt(firstLabel, _left);
      return;
    }

    paintAt(firstLabel, _left);
    final double leftOccupied =
        _left + measure(firstLabel) + _axisLabelGap;

    final double lastWidth = measure(lastLabel);
    final double lastLeft = _left + plotW - lastWidth;
    // 右端标签按右边界对齐；宁可压住最右边一点，也不要跑出画布。
    if (lastLeft > leftOccupied) {
      paintAt(lastLabel, lastLeft);
    }

    // 中间：空间够才画，不够就不画（不叠字优先于多一个信息点）。
    if (model.days.length > 3) {
      final int mid = model.days.length ~/ 2;
      final String midLabel = model.days[mid].shortLabel;
      if (midLabel != firstLabel && midLabel != lastLabel) {
        final double width = measure(midLabel);
        final double left = xFor(model.days[mid]) - width / 2;
        final bool fitsLeft = left > leftOccupied;
        final bool fitsRight = lastLeft - (left + width) > _axisLabelGap;
        if (fitsLeft && fitsRight) paintAt(midLabel, left);
      }
    }
  }

  /// 两个 x 轴标签之间至少留这么多像素。
  static const double _axisLabelGap = 10;

  void _fillDay(
    Canvas canvas,
    Rect plot,
    double x,
    double width,
    Paint paint,
  ) {
    final Rect r = Rect.fromLTRB(
      math.max(plot.left, x - width / 2),
      plot.top,
      math.min(plot.right, x + width / 2),
      plot.bottom,
    );
    if (r.width <= 0) return;
    canvas.drawRect(r, paint);
  }

  void _paintGrid(Canvas canvas, Rect plot, double Function(double) yAt) {
    final Paint line = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    final List<double> marks = <double>[
      model.minY,
      (model.minY + model.maxY) / 2,
      model.maxY,
    ];
    for (final double v in marks) {
      final double y = yAt(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), line);
      _paintText(
        canvas,
        v.toStringAsFixed(0),
        Offset(2, y - 6),
        const TextStyle(fontSize: Tokens.fontMicro, color: AppColors.inkFaint),
      );
    }
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    for (final PathMetric metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final double end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gap;
      }
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(SettlementChartPainter oldDelegate) {
    // ChartModel 没有值相等：每次重建 model 就重绘，成本可以接受。
    return oldDelegate.model != model ||
        oldDelegate.historyColor != historyColor ||
        oldDelegate.correctColor != correctColor ||
        oldDelegate.maintainColor != maintainColor;
  }
}
