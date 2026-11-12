import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';

/// 一条带符号的经验变动。
///
/// 它自己不决定分怎么算——算法在 [ValenceEngine]，这里只承载结果，
/// 明细页、图表打点、导出都读这个结构。
class ValenceEvent {
  const ValenceEvent({
    required this.id,
    required this.dayKey,
    required this.behaviorCode,
    required this.behaviorName,
    required this.valence,
    required this.axis,
    required this.baseScore,
    required this.qualityBonus,
    required this.efficiencyBonus,
    required this.normalizedScore,
    required this.weight,
    required this.stateMultiplier,
    required this.confidenceWeight,
    required this.exp,
    required this.confidence,
    this.notes = const [],
    this.breakdown = const {},
    this.estimated = false,
  });

  final String id;
  final DayKey dayKey;
  final String behaviorCode;
  final String behaviorName;
  final Valence valence;
  final ProjectAxis axis;

  /// 达标基础分（0–100）。
  final double baseScore;

  /// 精致加分（已在 40% 上限内）。
  final double qualityBonus;

  /// 极简效率加分（已在上限内，启发式）。
  final double efficiencyBonus;

  /// 归一化后的当日有效分（0–100）。
  final double normalizedScore;

  /// 项目权重。
  final double weight;

  /// 状态乘数（睡眠负债 / 损伤负荷 / 恢复债）。
  final double stateMultiplier;

  final double confidenceWeight;

  /// 最终 EXP，可为负。
  final double exp;

  final Confidence confidence;

  /// 中性说明，按顺序显示在明细页。
  final List<String> notes;

  /// 展开的中间量：base / quality / efficiency / overshoot / multiplier。
  final Map<String, double> breakdown;

  /// 是否为估算值（缺失数据但未清零）。
  final bool estimated;

  bool get isNegative => exp < 0;

  Map<String, Object?> toRow() => {
        'day_key': dayKey.iso,
        'behavior_code': behaviorCode,
        'behavior_name': behaviorName,
        'valence': valence.name,
        'axis': axis.name,
        'base_score': baseScore,
        'quality_bonus': qualityBonus,
        'efficiency_bonus': efficiencyBonus,
        'normalized_score': normalizedScore,
        'weight': weight,
        'state_multiplier': stateMultiplier,
        'confidence_weight': confidenceWeight,
        'exp': exp,
        'confidence': confidence.name,
        'notes': notes,
        'breakdown': breakdown,
        'estimated': estimated ? 1 : 0,
      };
}

/// 一条负向事件。允许被"归因去重"抑制（exp = 0 但保留痕迹）。
class NegativeEvent {
  const NegativeEvent({
    required this.dayKey,
    required this.behaviorCode,
    required this.behaviorName,
    required this.doseMinutes,
    required this.penaltyUnits,
    required this.exp,
    required this.rootCauseKey,
    required this.isPrimary,
    this.suppressedBy,
    this.consequences = const [],
    this.recoveryHints = const [],
    this.notes = const [],
  });

  final DayKey dayKey;
  final String behaviorCode;
  final String behaviorName;

  /// 折算成曲线的横轴（分钟当量或单位当量）。
  final double doseMinutes;

  /// 曲线输出（未乘 negScaleExp）。
  final double penaltyUnits;

  /// 最终扣分（负数）。被抑制时为 0。
  final double exp;

  /// 根因键，如 `sleep@2025-06-01`。同键只扣一次主因。
  final String rootCauseKey;

  /// 是否为主因事件。
  final bool isPrimary;

  /// 被谁抑制（主因键）。非空表示"这条是后果，不重复扣"。
  final String? suppressedBy;

  final List<String> consequences;
  final List<String> recoveryHints;
  final List<String> notes;

  bool get suppressed => suppressedBy != null;

  Map<String, Object?> toRow() => {
        'day_key': dayKey.iso,
        'behavior_code': behaviorCode,
        'behavior_name': behaviorName,
        'dose_minutes': doseMinutes,
        'penalty_units': penaltyUnits,
        'exp': exp,
        'root_cause_key': rootCauseKey,
        'is_primary': isPrimary ? 1 : 0,
        'suppressed_by': suppressedBy,
        'consequences': consequences,
        'recovery_hints': recoveryHints,
      };
}

/// 安全兜底警报。触发时当日**暂停结算**，不算分也不扣分。
class SafetyAlert {
  const SafetyAlert({
    required this.code,
    required this.title,
    required this.message,
    required this.advice,
    this.blocking = true,
  });

  final String code;
  final String title;
  final String message;

  /// 必须包含就医指引的措辞；App 不做诊断。
  final String advice;

  /// true = 暂停当日结算；false = 只提示。
  final bool blocking;
}
