/// 预测：两条线同时存在。
///
/// "若维持现状"（下行）与"若立即修正"（回升）必须一起画——
/// 只画一条会变成宿命论，只画上行会变成鸡汤。两条并置，
/// 用户自己看清代价与出路。
///
/// 所有输出都是**概率性估计**，UI 上禁止用确定口吻。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';import 'package:exp_ledger/domain/forecast/decay_model.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';

/// 预测输入。
class ProjectionInput {
  const ProjectionInput({
    required this.today,
    required this.currentAbility,
    required this.axis,
    required this.state,
    required this.recentDailyExp,
    this.horizonDays = 90,
    this.stepDays = 3,
    this.config = kDefaultConfig,
    this.isInterruption = false,
  });

  final DayKey today;
  final double currentAbility;
  final ProjectAxis axis;
  final StateVars state;

  /// 近 28 天的日均净经验（现实速率）。
  final double recentDailyExp;

  final int horizonDays;
  final int stepDays;
  final BalanceConfig config;

  /// 中断期（生病/受伤/旅行）不按"懈怠"处理，用纯衰减。
  final bool isInterruption;
}

/// 状态变量造成的拖累（0–1）。负债越高，"维持现状"越往下走。
double stateDrag(StateVars s, BalanceConfig cfg) {
  final sleep = (s.sleepDebtHours * 0.035).clampRange(0, 0.45);
  final damage = (s.damageLoad * 0.05).clampRange(0, 0.50);
  final recovery = (s.recoveryDebt * 0.02).clampRange(0, 0.20);
  return (sleep + damage + recovery).clampRange(0, 0.85);
}

/// 生成预测序列。第一个点就是今天（isProjection = false）。
List<ForecastPoint> project(ProjectionInput input) {
  final cfg = input.config;
  final drag = stateDrag(input.state, cfg);

  // 维持现状：现实速率 × (1 − 拖累)，再叠加去训练衰减。
  final maintainRate = input.recentDailyExp * (1 - drag);

  // 立即修正：负债开始回补，拖累只剩两成，并额外获得恢复红利。
  final repairBonus = (input.state.sleepDebtHours * 0.6 +
          input.state.damageLoad * 0.8) *
      cfg.expPerPoint *
      0.12;
  final correctRate = input.recentDailyExp * (1 - drag * 0.2) + repairBonus;

  final points = <ForecastPoint>[];
  var abilityNow = input.currentAbility;
  var abilityFix = input.currentAbility;

  for (var t = 0; t <= input.horizonDays; t += input.stepDays) {
    if (t > 0) {
      final base = detrain(
        current: abilityNow,
        days: input.isInterruption ? input.stepDays : 0,
        axis: input.axis,
        floor: input.currentAbility * 0.6,
      );
      // 维持线：速率努力与衰减同时作用，取较小者方向的保守估计。
      abilityNow = (base + maintainRate * input.stepDays)
          .clampRange(0, 120)
          .toDouble();
      abilityFix = (abilityFix + correctRate * input.stepDays)
          .clampRange(0, 120)
          .toDouble();
    }
    final half = bandHalfWidth(t);
    final band = bandAround(abilityNow, half);
    points.add(ForecastPoint(
      day: input.today.addDays(t),
      maintain: abilityNow,
      correct: abilityFix,
      low: band.low,
      high: band.high,
      confidence: t == 0 ? 1 : forecastConfidence(t),
      isProjection: t > 0,
    ));
  }
  return points;
}

/// 机会成本：明确写出"不动会损失什么"。
///
/// 全部是估算口径，禁止写成确定句。
List<String> opportunityCost({
  required ProjectAxis axis,
  required double currentAbility,
  required StateVars state,
  required int horizonDays,
  required int pendingReviews,
}) {
  final out = <String>[];

  final future = detrain(
    current: currentAbility,
    days: horizonDays,
    axis: axis,
  );
  if (future < currentAbility - 1) {
    out.add('这 $horizonDays 天不动，${
        axis.label
    }这一维预计会回落到 ${future.round()} 左右（去训练效应估算，非确定值）。');
  }

  if (pendingReviews > 0) {
    out.add('这 $pendingReviews 个词如果三天内不复习，按当前记忆强度估算，'
        '保持率会掉到 40% 以下。');
  }

  if (state.sleepDebtHours > 1) {
    out.add('睡眠负债 ${state.sleepDebtHours.toStringAsFixed(1)} 小时不处理，'
        '接下来一周的加分权重会被压掉约 ${(stateDrag(state, kDefaultConfig) * 100).round()}%。');
  }

  if (out.isEmpty) {
    out.add('当前没有明显的机会成本在累积，继续保持。');
  }
  return out;
}

/// 预测的口径声明，必须随图一起显示。
const String kForecastDisclaimer =
    '虚线是概率性估计，不是承诺；每次有新数据都会重算。'
    '实线是已经发生的，虚线只是"按现在的样子走下去大概会怎样"。';

/// 供图表使用的辅助：把 90 天压缩成 30 个采样点。
List<ForecastPoint> downsample(List<ForecastPoint> points, int target) {
  if (points.length <= target) return points;
  final stride = (points.length / target).ceil();
  final out = <ForecastPoint>[];
  for (var i = 0; i < points.length; i += stride) {
    out.add(points[i]);
  }
  if (out.last.day != points.last.day) out.add(points.last);
  return out;
}

/// 简单线性回归，用于从历史里取趋势斜率（不含预测）。
double slopeOf(List<double> values) {
  if (values.length < 2) return 0;
  final n = values.length;
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
  for (var i = 0; i < n; i++) {
    sx += i;
    sy += values[i];
    sxy += i * values[i];
    sxx += i * i;
  }
  final denom = n * sxx - sx * sx;
  if (denom == 0) return 0;
  return (n * sxy - sx * sy) / denom;
}

/// 移动中位数，用于给效率基线做稳健估计。
double medianOf(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}
