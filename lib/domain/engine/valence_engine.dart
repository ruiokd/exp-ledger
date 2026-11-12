/// 加减分引擎总入口。
///
/// 一条记录进来，出去一个带符号的 [ValenceEvent] 或 [NegativeEvent]。
/// 所有判断都在这里串起来，但每个判断本身都住在自己的文件里：
///
///   基础分 → score_curves      精致加分 → quality_bonus
///   效率加分 → efficiency_bonus 超额分流 → overshoot_router
///   状态折价 → state_multiplier 归因去重 → attribution
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/engine/attribution.dart';
import 'package:exp_ledger/domain/engine/efficiency_bonus.dart';
import 'package:exp_ledger/domain/engine/overshoot_router.dart';
import 'package:exp_ledger/domain/engine/quality_bonus.dart';
import 'package:exp_ledger/domain/engine/score_curves.dart';
import 'package:exp_ledger/domain/engine/state_multiplier.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';

/// 一次结算需要的环境。
class EngineContext {
  const EngineContext({
    required this.dayKey,
    required this.state,
    required this.config,
    this.load,
    this.nextBand = AcwrBand.low,
    this.baselineEfficiency = 0,
    this.existingRootKeys = const {},
    this.hoursSinceSameMuscle = 999,
    this.fatigued = false,
  });

  final DayKey dayKey;
  final StateVars state;
  final BalanceConfig config;
  final LoadIndex? load;

  /// 如果加上今天这次训练，ACWR 会落在哪一档。
  final AcwrBand nextBand;

  /// 近 28 天同行为的效率基线（中位数）。0 表示还没有基线。
  final double baselineEfficiency;

  /// 今天与昨天已存在的根因键，用于归因去重。
  final Set<String> existingRootKeys;

  final int hoursSinceSameMuscle;
  final bool fatigued;
}

/// 单条记录的结算产物。
class DraftOutcome {
  const DraftOutcome({
    this.positive,
    this.negative,
    this.damageUnits = 0,
    this.notes = const [],
    this.skipped = false,
  });

  final ValenceEvent? positive;
  final NegativeEvent? negative;

  /// 转成损伤负荷的单位数（过量风险、受伤）。
  final double damageUnits;

  final List<String> notes;

  /// 计划外中断期这类"不产出分数"的记录。
  final bool skipped;
}

class ValenceEngine {
  const ValenceEngine();

  DraftOutcome evaluate(DraftEntry draft, EngineContext ctx) {
    if (draft.isInterruption) {
      return DraftOutcome(
        notes: ['中断期：不扣成长分，能力值只按自然衰减走。'],
        skipped: true,
      );
    }
    switch (draft.valence) {
      case Valence.negative:
        return _evaluateNegative(draft, ctx);
      case Valence.offPlan:
        return _evaluateOffPlan(draft, ctx);
      case Valence.positive:
      case Valence.neutral:
        return _evaluatePositive(draft, ctx);
    }
  }

  // ------------------------------------------------------------ 正向

  DraftOutcome _evaluatePositive(DraftEntry draft, EngineContext ctx) {
    final cfg = ctx.config;
    final base = baseScoreFor(draft.doseFraction, cfg);
    final quality = qualityFromMetrics(draft.metrics);
    final qBonus = qualityBonusFor(baseScore: base, quality: quality, cfg: cfg);
    final ratio = efficiencyRatioOf(draft.metrics);
    final eBonus = efficiencyBonusFor(
      baseScore: base,
      ratio: ratio,
      baselineRatio: ctx.baselineEfficiency,
      cfg: cfg,
    );

    final score = (base + qBonus + eBonus).clampRange(0, 100);
    final mult = multipliersFor(ctx.state, cfg).combined;
    final weight = weightFor(draft.axis, cfg);
    final cw = draft.confidence.weight;
    final exp = score * weight * mult * cw * cfg.expPerPoint;

    final notes = <String>[
      if (!quality.isEmpty) qualityNote(quality),
      if (eBonus > 0)
        efficiencyNote(ratio: ratio, baseline: ctx.baselineEfficiency),
    ]..removeWhere((s) => s.isEmpty);

    return DraftOutcome(
      positive: ValenceEvent(
        id: '${draft.idempotencyKey}#p',
        dayKey: draft.dayKey,
        behaviorCode: draft.behaviorCode,
        behaviorName: draft.behaviorCode,
        valence: draft.valence,
        axis: draft.axis,
        baseScore: base,
        qualityBonus: qBonus,
        efficiencyBonus: eBonus,
        normalizedScore: score,
        weight: weight,
        stateMultiplier: mult,
        confidenceWeight: cw,
        exp: exp,
        confidence: draft.confidence,
        notes: notes,
        estimated: draft.doseFraction <= 0,
        breakdown: {
          'base': base,
          'quality': qBonus,
          'efficiency': eBonus,
          'multiplier': mult,
          'weight': weight,
          'confidence': cw,
          'exp_per_point': cfg.expPerPoint,
        },
      ),
    );
  }

  // ------------------------------------------------------------ 负向

  DraftOutcome _evaluateNegative(DraftEntry draft, EngineContext ctx) {
    final cfg = ctx.config;
    // 剂量取"熬夜越界"与"睡眠缺口"中更严重的那个——
    // 两者描述同一晚，相加会把一次熬夜罚两遍。
    // 注意：不能把变量叫 `late`——它是 Dart 的内置标识符，
    // 出现在声明位置会直接语法错误（tree-sitter 与 analyzer 都会报）。
    final lateMinutes = draft.metrics['late_minutes'] ?? 0;
    final gapMinutes = (draft.metrics['gap_hours'] ?? 0) * 60;
    final explicit = draft.metrics['curve_minutes'];
    final dose =
        explicit ?? (lateMinutes > gapMinutes ? lateMinutes : gapMinutes);
    final penalty = negativeCurve(dose, cfg);
    final attr = resolveAttribution(
      behaviorCode: draft.behaviorCode,
      day: draft.dayKey,
      answers: draft.answers,
      existingRootKeys: ctx.existingRootKeys,
    );

    final suppressed = attr.isSuppressed;
    final exp = suppressed ? 0.0 : -penalty * cfg.negScaleExp * draft.confidence.weight;

    return DraftOutcome(
      negative: NegativeEvent(
        dayKey: draft.dayKey,
        behaviorCode: draft.behaviorCode,
        behaviorName: draft.behaviorCode,
        doseMinutes: dose,
        penaltyUnits: penalty,
        exp: exp,
        rootCauseKey: attr.rootCauseKey,
        isPrimary: !suppressed,
        suppressedBy: attr.suppressedBy,
        consequences: suppressed ? const ['已由主因事件计入'] : const [],
        recoveryHints: draft.notes.where((n) => n.isNotEmpty).toList(),
        notes: [
          if (suppressed) consequenceNote(attr),
        ]..removeWhere((s) => s.isEmpty),
      ),
    );
  }

  // ------------------------------------------------------------ 计划外

  DraftOutcome _evaluateOffPlan(DraftEntry draft, EngineContext ctx) {
    final cfg = ctx.config;
    final kind = (draft.metrics['offplan_kind'] ?? 0).round();

    // 3 = 中断期（生病/受伤/加班/旅行）：不产出分数。
    if (kind == 3) {
      return DraftOutcome(
        damageUnits: draft.metrics['injury_load'] ?? 0,
        notes: ['中断期：不扣成长分，图上会用特殊底色标出。'],
        skipped: true,
      );
    }

    final decision = routeOvershoot(
      plannedDose: 1,
      actualDose: draft.doseFraction <= 0 ? 1 : draft.doseFraction,
      nextBand: ctx.nextBand,
      muscleRecovered: ctx.hoursSinceSameMuscle >= 48,
      fatigued: ctx.fatigued,
      cfg: cfg,
    );

    if (!decision.beneficial) {
      return DraftOutcome(
        damageUnits: decision.damageUnits,
        notes: [decision.reason, ...decision.warnings],
      );
    }

    // 有益超额：按边际递减计分，但总额封顶，避免"越加练越赚"。
    final base = baseScoreFor(decision.creditedRatio.clampRange(0, 1.2), cfg);
    final mult = multipliersFor(ctx.state, cfg).combined;
    final weight = weightFor(draft.axis, cfg);
    final cw = draft.confidence.weight;
    final score = base.clampRange(0, 100);
    final exp = score * weight * mult * cw * cfg.expPerPoint;

    return DraftOutcome(
      positive: ValenceEvent(
        id: '${draft.idempotencyKey}#p',
        dayKey: draft.dayKey,
        behaviorCode: draft.behaviorCode,
        behaviorName: draft.behaviorCode,
        valence: Valence.positive,
        axis: draft.axis,
        baseScore: base,
        qualityBonus: 0,
        efficiencyBonus: 0,
        normalizedScore: score,
        weight: weight,
        stateMultiplier: mult,
        confidenceWeight: cw,
        exp: exp,
        confidence: draft.confidence,
        notes: [decision.reason],
        breakdown: {
          'base': base,
          'credited_ratio': decision.creditedRatio,
          'excess_ratio': decision.excessRatio,
          'multiplier': mult,
        },
      ),
    );
  }
}

/// 项目权重。数值实验室里改权重，这里立刻生效。
double weightFor(ProjectAxis axis, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  return switch (axis) {
    ProjectAxis.strength => c.weightStrength,
    ProjectAxis.cardio => c.weightCardio,
    ProjectAxis.memory => c.weightMemory,
    ProjectAxis.writing => c.weightWriting,
    ProjectAxis.discipline => c.weightRestraint,
  };
}
