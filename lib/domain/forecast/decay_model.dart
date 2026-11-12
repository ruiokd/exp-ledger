/// 衰减模型与置信带。
///
/// 衰减不是惩罚，是生理事实：停止刺激后能力会向基线回落，
/// 不同维度的回落速度不一样（心肺掉得比力量快，词汇掉得比写作慢）。
///
/// 这些时间常数是**经验近似**，不是实验测得的精确值，
/// 图例上统一标注"去训练效应（估算）"。
library;

import 'dart:math' as math;

import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';

/// 各维度的去训练时间常数（天）。数值越大，掉得越慢。
double detrainTau(ProjectAxis axis) => switch (axis) {
      ProjectAxis.strength => 21,
      ProjectAxis.cardio => 12,
      ProjectAxis.memory => 30,
      ProjectAxis.writing => 45,
      ProjectAxis.discipline => 14,
    };

/// 停止训练 [days] 天后，能力值从 [current] 回落到多少。
///
/// 形态：向个人基线 [floor] 指数逼近，而不是一路掉到 0——
/// "完全归零"在生理上不成立，在心理上也没必要。
double detrain({
  required double current,
  required int days,
  required ProjectAxis axis,
  double? floor,
}) {
  if (days <= 0) return current;
  final base = floor ?? current * 0.65;
  final b = base.clampRange(0, current);
  final tau = detrainTau(axis);
  return b + (current - b) * math.exp(-days / tau);
}

/// 置信带半宽：预测越远越宽。
double bandHalfWidth(int horizonDays, {double base = 2.0, double growth = 0.09}) =>
    base + growth * horizonDays;

/// 预测的可信度，随天数衰减。
double forecastConfidence(int horizonDays) => 1 / (1 + horizonDays / 45.0);

/// 把点估计和半宽合成区间。
({double low, double high}) bandAround(double value, double halfWidth) =>
    (low: value - halfWidth, high: value + halfWidth);
