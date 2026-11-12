/// 睡眠指标换算。
///
/// 全部为算术定义（时长、差额、效率），没有需要"相信"的模型，
/// 因此这一组数据的置信度只取决于用户填得准不准。
library;

import 'dart:math' as math;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';

/// 从入睡到醒来的时长（分钟），自动处理跨零点。
int sleepWindowMinutes({
  required MinuteOfDay bed,
  required MinuteOfDay wake,
}) {
  final diff = (wake.minutes - bed.minutes + 1440) % 1440;
  // 恰好在床上待满 24 小时的极端情况，按 1440 处理。
  return diff == 0 ? 1440 : diff;
}

/// 有效睡眠时长 = 在床时长 − 中途清醒总时长。
int effectiveSleepMinutes({
  required MinuteOfDay bed,
  required MinuteOfDay wake,
  required int awakenings,
  required double avgAwakeMinutes,
}) {
  final window = sleepWindowMinutes(bed: bed, wake: wake);
  final awake = (awakenings <= 0 ? 0.0 : awakenings * avgAwakeMinutes)
      .clampRange(0, window.toDouble());
  return (window - awake).round();
}

/// 睡眠效率 = 有效睡眠 / 在床时长。常用参考线 85%。
double sleepEfficiency({
  required int effectiveMinutes,
  required int windowMinutes,
}) {
  if (windowMinutes <= 0) return 0;
  return (effectiveMinutes / windowMinutes).clampRange(0, 1);
}

/// 熬夜越界分钟数：入睡时间比个人界线晚了多少。
/// 未越界返回 0（而不是负数），因为"早睡"不产生负向剂量。
int lateSleepMinutes({
  required MinuteOfDay bed,
  required SleepLine line,
}) {
  final delta = bed.forwardFrom(MinuteOfDay(line.totalMinutes));
  // 差值超过 12 小时说明其实是早睡（界线 00:20、实际 21:00 → 差值 1240）。
  return delta > 720 ? 0 : delta;
}

/// 睡眠缺口（小时）：需要多少 − 实际有效多少，下限 0。
double sleepGapHours({
  required double effectiveHours,
  required double needHours,
}) {
  final gap = needHours - effectiveHours;
  return gap < 0 ? 0 : gap;
}

/// 入睡时间相对近期规律的偏移（分钟）。稳定性是"精致加分"的一个维度。
///
/// 以 04:00 为日界做环形平均，避免 23:50 与 00:10 被判成差 23 小时。
int bedtimeIrregularityMinutes({
  required MinuteOfDay bed,
  required List<MinuteOfDay> recent,
}) {
  if (recent.isEmpty) return 0;
  const pivot = 240;
  const twoPi = 2 * math.pi;
  var sumSin = 0.0;
  var sumCos = 0.0;
  for (final b in recent) {
    final angle = (b.minutes - pivot) / 1440 * twoPi;
    sumSin += math.sin(angle);
    sumCos += math.cos(angle);
  }
  if (sumSin.abs() < 1e-9 && sumCos.abs() < 1e-9) return 0;
  final meanAngle = math.atan2(sumSin, sumCos);
  final meanMinutes = (pivot + meanAngle / twoPi * 1440) % 1440;
  var diff = (bed.minutes - meanMinutes).abs() % 1440;
  if (diff > 720) diff = 1440 - diff;
  return diff.round();
}

/// 一日睡眠的完整解读，回执与结算都用它。
class SleepOutcome {
  const SleepOutcome({
    required this.effectiveHours,
    required this.windowHours,
    required this.efficiency,
    required this.lateMinutes,
    required this.gapHours,
    required this.isLate,
    required this.meetsNeed,
  });

  final double effectiveHours;
  final double windowHours;
  final double efficiency;
  final int lateMinutes;
  final double gapHours;
  final bool isLate;
  final bool meetsNeed;

  String get durationLabel {
    final h = effectiveHours.floor();
    final m = ((effectiveHours - h) * 60).round();
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }
}

SleepOutcome evaluateSleep({
  required MinuteOfDay bed,
  required MinuteOfDay wake,
  required int awakenings,
  required double avgAwakeMinutes,
  required UserProfile profile,
}) {
  final window = sleepWindowMinutes(bed: bed, wake: wake);
  final effective = effectiveSleepMinutes(
    bed: bed,
    wake: wake,
    awakenings: awakenings,
    avgAwakeMinutes: avgAwakeMinutes,
  );
  final effHours = effective / 60.0;
  final late = lateSleepMinutes(bed: bed, line: profile.sleepLine);
  return SleepOutcome(
    effectiveHours: effHours,
    windowHours: window / 60.0,
    efficiency:
        sleepEfficiency(effectiveMinutes: effective, windowMinutes: window),
    lateMinutes: late,
    gapHours: sleepGapHours(
      effectiveHours: effHours,
      needHours: profile.sleepNeedHours,
    ),
    isLate: late > 0,
    meetsNeed: effHours >= profile.sleepNeedHours,
  );
}

/// 分钟数 → "1 小时 50 分"。
String humanizeMinutes(int minutes) {
  if (minutes <= 0) return '0 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m 分钟';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分';
}

/// 保留至多一位小数的小时显示。
String humanizeHours(double hours) {
  final v = hours.roundTo(1);
  final s = v == v.roundTo(0) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$s 小时';
}
