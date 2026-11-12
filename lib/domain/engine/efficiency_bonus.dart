/// 极简加分（效率加分）。
///
/// 语义：用更少的投入获得同等或更高的有效刺激。
/// **这是启发式指标，不是生理学公式**——UI 上必须标注"效率加分（启发式）"，
/// 且总额受 [BalanceConfig.efficiencyBonusCap]（默认基础分的 15%）硬上限约束。
///
/// 为什么需要它：如果只按"做了多少"给分，最省力的做法永远是拉长时间，
/// 这会奖励低效劳动。效率加分把"更短时间拿到同样刺激"标出来。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// 从中间量里算"单位投入产出的有效量"。
/// 返回 0 表示这个行为没有可比的效率口径（那就干脆不加分）。
double efficiencyRatioOf(Map<String, double> m) {
  if (m.containsKey('effective_sets') && m.containsKey('session_minutes')) {
    final minutes = m['session_minutes'] ?? 0;
    if (minutes <= 0) return 0;
    return (m['effective_sets'] ?? 0) / (minutes / 60);
  }

  if (m.containsKey('consolidated_words') && m.containsKey('words')) {
    final words = m['words'] ?? 0;
    if (words <= 0) return 0;
    // 稳固词率：一次学习里真正留下来的比例。
    return (m['consolidated_words'] ?? 0) / words;
  }

  if (m.containsKey('stimulus') && m.containsKey('minutes')) {
    final minutes = m['minutes'] ?? 0;
    if (minutes <= 0) return 0;
    return (m['stimulus'] ?? 0) / minutes; // 即 MET
  }

  if (m.containsKey('effective_minutes') && m.containsKey('minutes')) {
    final minutes = m['minutes'] ?? 0;
    if (minutes <= 0) return 0;
    return (m['effective_minutes'] ?? 0) / minutes;
  }

  if (m.containsKey('effective_words') && m.containsKey('words')) {
    final words = m['words'] ?? 0;
    if (words <= 0) return 0;
    return (m['effective_words'] ?? 0) / words;
  }

  return 0;
}

/// 效率加分（已封顶）。
///
/// baseline 取个人近 28 天同行为的效率中位数；没有基线时返回 0——
/// 不给"第一次做就效率很高"发奖，那只是数据不足。
double efficiencyBonusFor({
  required double baseScore,
  required double ratio,
  required double baselineRatio,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  if (baseScore <= 0 || ratio <= 0 || baselineRatio <= 0) return 0;
  final gain = (ratio / baselineRatio - 1).clampRange(0, 1);
  if (gain <= 0) return 0;
  final raw = baseScore * c.efficiencyWeight * gain;
  final cap = baseScore * c.efficiencyBonusCap;
  return raw < cap ? raw : cap;
}

/// 效率加分的说明文案。明确写出"启发式"三个字。
String efficiencyNote({
  required double ratio,
  required double baseline,
}) {
  if (baseline <= 0 || ratio <= 0) return '';
  final delta = (ratio / baseline - 1) * 100;
  if (delta < 1) return '';
  return '单位时间的有效刺激比你的近 28 天基线高约 ${delta.round()}%'
      '（效率加分，启发式指标，非生理学公式）。';
}

/// 效率加分的上限比例，供 UI 显示"已封顶"。
double efficiencyCapRatio(BalanceConfig? cfg) =>
    (cfg ?? kDefaultConfig).efficiencyBonusCap;
