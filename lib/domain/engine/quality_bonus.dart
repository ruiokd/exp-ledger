/// 精致加分。
///
/// 设计约束（写死在代码里，防止以后被"优化"掉）：
///   · 质量维度只能加分，不能减分——负向已经有专门的通道，
///     这里再扣就成了双罚。
///   · 无论质量多好，加分总额 **不得超过基础分的 40%**。
///     这是防"越精致越卷"的硬上限，用 min() 截断，不是加权平均。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// 质量维度拆解，用于明细页展示"这 0.3 分是哪儿来的"。
class QualityBreakdown {
  const QualityBreakdown(this.dimensions);

  final Map<String, double> dimensions;

  /// 0–1 的综合质量分。维度为空时返回 0（不加分）。
  double get score {
    if (dimensions.isEmpty) return 0;
    final values = dimensions.values.toList();
    return (values.reduce((a, b) => a + b) / values.length).clampRange(0, 1);
  }

  bool get isEmpty => dimensions.isEmpty;
}

/// 从推导出来的中间量里提取质量维度。
///
/// 每个维度都对应一个可解释的行为事实（比如"入睡时间是否稳定"），
/// 不是拍脑袋的权重。看不懂的维度宁可不加，也不编一个。
QualityBreakdown qualityFromMetrics(Map<String, double> m) {
  final dims = <String, double>{};

  if (m.containsKey('efficiency') && m.containsKey('effective_hours')) {
    // 睡眠：效率（85% 参考线）+ 是否满足需求
    final eff = m['efficiency'] ?? 0;
    dims['睡眠效率'] = ((eff - 0.75) / 0.25).clampRange(0, 1);
    final need = m['sleep_need_hours'] ?? 7.5;
    final got = m['effective_hours'] ?? 0;
    dims['睡眠充足度'] = (got / (need <= 0 ? 7.5 : need)).clampRange(0, 1);
  }

  if (m.containsKey('intensity_factor') && m.containsKey('compensation_factor')) {
    // 训练：强度是否落在增肌有效区间 + 是否代偿
    final rir = m['rir'] ?? 4;
    final inRange = (rir >= 1 && rir <= 3) ? 1.0 : (rir <= 5 ? 0.6 : 0.3);
    dims['强度区间'] = inRange;
    dims['动作质量'] = (m['compensation_factor'] ?? 1).clampRange(0, 1);
  }

  if (m.containsKey('active_recall_ratio')) {
    // 记忆：主动提取比例（这是保持率的最大变量）
    dims['主动提取'] = (m['active_recall_ratio'] ?? 0).clampRange(0, 1);
  }

  if (m.containsKey('protein_ratio')) {
    dims['蛋白质达标'] = (m['protein_ratio'] ?? 0).clampRange(0, 1);
    dims['食物质量'] = (m['quality_factor'] ?? 0).clampRange(0, 1);
  }

  if (m.containsKey('cognitive_minutes') && m.containsKey('minutes')) {
    // 阅读：认知当量 / 实际时长 = 加工深度
    final cog = m['cognitive_minutes'] ?? 0;
    final min = m['minutes'] ?? 1;
    dims['加工深度'] = (cog / (min <= 0 ? 1 : min) / 1.3).clampRange(0, 1);
  }

  if (m.containsKey('effective_words') && m.containsKey('words')) {
    final eff = m['effective_words'] ?? 0;
    final w = m['words'] ?? 1;
    dims['表达多样性'] = (eff / (w <= 0 ? 1 : w) / 1.15).clampRange(0, 1);
  }

  return QualityBreakdown(dims);
}

/// 精致加分的实际分值（已封顶）。
double qualityBonusFor({
  required double baseScore,
  required QualityBreakdown quality,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  if (baseScore <= 0 || quality.isEmpty) return 0;
  final raw = baseScore * quality.score * c.qualityWeight;
  final cap = baseScore * c.qualityBonusCap;
  return raw < cap ? raw : cap;
}

/// 给用户看的一句话解释（中性，不含"优秀/完美"）。
String qualityNote(QualityBreakdown q) {
  if (q.isEmpty) return '';
  final names = q.dimensions.keys.join('、');
  return '质量维度：$names。这部分加分有 40% 的硬上限，不会越刷越多。';
}
