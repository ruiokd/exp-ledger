/// 计分曲线。正向、负向、超额三种形状都集中在这里，
/// 任何"分数怎么来的"问题都能在这一个文件里回答。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// 正向基础分：剂量比例 → 0–100。
///
/// 指数 <1（默认 0.8）意味着"做到一半也有六成基础分"——
/// 这是故意的：差一点全废最容易让人放弃记录。
double baseScoreFor(double doseFraction, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  if (doseFraction <= 0) return 0;
  final capped = doseFraction.clampRange(0, 1);
  return 100 * powSafe(capped, c.partialDoseExponent);
}

/// 超额部分的边际递减：第 4 组的价值低于第 1 组。
///
/// ratio ≤ 1 时原样返回；ratio > 1 时返回 1 + (ratio−1)^0.6，
/// 增长恒定为正但斜率递减——单测会断言这一点。
double marginalDecay(double ratio, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  if (ratio <= 0) return 0;
  if (ratio <= 1) return ratio;
  return 1 + powSafe(ratio - 1, c.overshootExponent);
}

/// 负向扣分的剂量曲线（分钟当量 → 扣分单位）。
///
/// 委托给 BalanceConfig，保证"数值实验室里改 k1/k2/k3 立刻生效"。
double negativeCurve(double minutes, [BalanceConfig? cfg]) =>
    (cfg ?? kDefaultConfig).negativeDoseCurve(minutes);

/// 负向 EXP（负数）。
double negativeExp(double minutes, [BalanceConfig? cfg]) =>
    (cfg ?? kDefaultConfig).negativeDoseExp(minutes);

/// 总分归一：把若干项分数压回 0–100，保证跨项目可比。
double normalizeTo100(double raw, double referenceMax) {
  if (referenceMax <= 0) return 0;
  return (raw / referenceMax * 100).clampRange(0, 100);
}
