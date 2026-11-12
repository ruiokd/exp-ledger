/// 结算流水线。把一天里所有记录压成一份 [DaySettlement]。
///
/// 顺序是固定的，且每一步都是纯函数：
///   0 安全闸 → 1 逐条求值 → 2 归因去重 → 3 汇总 → 4 状态变量推进 → 5 等级 → 6 回补路径
///
/// 因为全程无副作用，历史数据修正 + 级联重算只需要从某天重跑一遍。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/engine/level_curve.dart';
import 'package:exp_ledger/domain/engine/recovery_planner.dart';
import 'package:exp_ledger/domain/engine/safety_gate.dart';
import 'package:exp_ledger/domain/engine/valence_engine.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';
import 'package:exp_ledger/domain/science/damage_load.dart';

class SettlementInput {
  const SettlementInput({
    required this.dayKey,
    required this.drafts,
    required this.stateBefore,
    required this.levelBefore,
    required this.load,
    required this.config,
    this.nextBand = AcwrBand.low,
    this.baselineEfficiency = 0,
    this.existingRootKeys = const {},
    this.hoursSinceSameMuscle = 999,
    this.fatigued = false,
    this.consecutiveHighIntensityDays = 0,
  });

  final DayKey dayKey;
  final List<DraftEntry> drafts;
  final StateVars stateBefore;
  final LevelState levelBefore;
  final LoadIndex load;
  final BalanceConfig config;
  final AcwrBand nextBand;
  final double baselineEfficiency;
  final Set<String> existingRootKeys;
  final int hoursSinceSameMuscle;
  final bool fatigued;
  final int consecutiveHighIntensityDays;
}

class SettlementPipeline {
  const SettlementPipeline();

  DaySettlement settle(SettlementInput input) {
    final cfg = input.config;

    // ---- 0. 安全闸：先判安全，再谈算分 ----
    final alert = const SafetyGate().check(
      drafts: input.drafts,
      state: input.stateBefore,
      consecutiveHighIntensityDays: input.consecutiveHighIntensityDays,
    );
    if (alert != null && alert.blocking) {
      return DaySettlement(
        dayKey: input.dayKey,
        positives: const [],
        negatives: const [],
        positiveExp: 0,
        negativeExp: 0,
        status: SettlementStatus.paused,
        stateBefore: input.stateBefore,
        stateAfter: input.stateBefore,
        alert: alert,
        notes: const ['今日暂停结算：先照顾身体，账本明天再算。'],
        levelBefore: input.levelBefore.level,
        levelAfter: input.levelBefore.level,
        bufferAfter: input.levelBefore.buffer,
        isInterruption: input.drafts.every((d) => d.isInterruption),
      );
    }

    // ---- 1. 逐条求值 ----
    final ctx = EngineContext(
      dayKey: input.dayKey,
      state: input.stateBefore,
      config: cfg,
      load: input.load,
      nextBand: input.nextBand,
      baselineEfficiency: input.baselineEfficiency,
      existingRootKeys: input.existingRootKeys,
      hoursSinceSameMuscle: input.hoursSinceSameMuscle,
      fatigued: input.fatigued,
    );

    final engine = const ValenceEngine();
    final positives = <ValenceEvent>[];
    final rawNegatives = <NegativeEvent>[];
    var damageUnits = 0.0;
    final notes = <String>[];

    for (final draft in input.drafts) {
      final outcome = engine.evaluate(draft, ctx);
      if (outcome.positive != null) positives.add(outcome.positive!);
      if (outcome.negative != null) rawNegatives.add(outcome.negative!);
      damageUnits += outcome.damageUnits;
      notes.addAll(outcome.notes);
    }

    // ---- 2. 归因去重 ----
    final negatives = _dedupe(rawNegatives);

    // ---- 3. 汇总 ----
    final positiveExp =
        positives.fold<double>(0, (sum, e) => sum + e.exp);
    final negativeExp =
        negatives.fold<double>(0, (sum, e) => sum + e.exp);

    // ---- 4. 状态变量推进 ----
    final stateAfter = _advanceState(
      before: input.stateBefore,
      drafts: input.drafts,
      negatives: negatives,
      band: input.nextBand,
      consecutiveHighDays: input.consecutiveHighIntensityDays,
      damageUnits: damageUnits,
      cfg: cfg,
    );

    // ---- 5. 等级 ----
    final levelAfter = applyExp(
      input.levelBefore,
      positiveExp + negativeExp,
      cfg,
    );

    // ---- 6. 回补路径 ----
    final recovery = buildRecoveryPlan(
      negatives: negatives.where((n) => !n.suppressed).toList(),
      state: stateAfter,
    );

    final dropNote = explainDrop(
      before: input.levelBefore,
      after: levelAfter,
      state: stateAfter,
      cfg: cfg,
    );

    return DaySettlement(
      dayKey: input.dayKey,
      positives: positives,
      negatives: negatives,
      positiveExp: positiveExp,
      negativeExp: negativeExp,
      status: SettlementStatus.settled,
      stateBefore: input.stateBefore,
      stateAfter: stateAfter,
      alert: alert,
      notes: [
        ...notes,
        if (alert != null) '${alert.title}：${alert.message} ${alert.advice}',
        if (dropNote != null) dropNote,
      ].where((s) => s.isNotEmpty).toList(),
      recoveryPlan: recovery,
      levelBefore: input.levelBefore.level,
      levelAfter: levelAfter.level,
      bufferAfter: levelAfter.buffer,
      isInterruption: input.drafts.every((d) => d.isInterruption),
    );
  }

  /// 同根因只保留一条主因，其余记为后果（exp = 0）。
  List<NegativeEvent> _dedupe(List<NegativeEvent> raw) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < raw.length; i++) {
      groups.putIfAbsent(raw[i].rootCauseKey, () => <int>[]).add(i);
    }

    final result = List<NegativeEvent?>.filled(raw.length, null);
    for (final entry in groups.entries) {
      final idxs = entry.value;
      var primary = idxs.first;
      for (final i in idxs) {
        if (raw[i].penaltyUnits > raw[primary].penaltyUnits) primary = i;
      }
      result[primary] = raw[primary];
      for (final i in idxs) {
        if (i == primary) continue;
        final n = raw[i];
        result[i] = NegativeEvent(
          dayKey: n.dayKey,
          behaviorCode: n.behaviorCode,
          behaviorName: n.behaviorName,
          doseMinutes: n.doseMinutes,
          penaltyUnits: n.penaltyUnits,
          exp: 0,
          rootCauseKey: n.rootCauseKey,
          isPrimary: false,
          suppressedBy: entry.key,
          consequences: n.consequences,
          recoveryHints: n.recoveryHints,
          notes: const ['作为同一根因的后果记录，不重复扣分。'],
        );
      }
    }
    return result.whereType<NegativeEvent>().toList();
  }

  StateVars _advanceState({
    required StateVars before,
    required List<DraftEntry> drafts,
    required List<NegativeEvent> negatives,
    required AcwrBand band,
    required int consecutiveHighDays,
    required double damageUnits,
    required BalanceConfig cfg,
  }) {
    // 睡眠：先按昨晚质量衰减，再加上今天新产生的缺口。
    double sleptHours = 0;
    double needHours = 7.5;
    var hasSleep = false;
    for (final d in drafts) {
      if (d.behaviorCode == 'sleep') {
        hasSleep = true;
        sleptHours = d.metrics['effective_hours'] ?? 0;
        needHours = d.metrics['sleep_need_hours'] ?? 7.5;
      }
    }

    var sleepDebt = before.sleepDebtHours;
    if (hasSleep) {
      final decayed = before.decayOvernight(
        sleepDebtDecayPerNight: cfg.sleepDebtDecayPerNight,
        damageDecayPerDay: cfg.damageDecayPerDay,
        sleptHours: sleptHours,
        sleepNeedHours: needHours,
      );
      sleepDebt = decayed.sleepDebtHours;
      final gap = needHours - sleptHours;
      if (gap > 0) sleepDebt += gap;
    }

    // 损伤：新增 − 当日衰减。
    final contribution = damageDelta(
      band: band,
      consecutiveHighDays: consecutiveHighDays,
      sleepDebtHours: sleepDebt,
      overshootUnits: damageUnits,
      injuryLoad: 0,
      cfg: cfg,
    );
    final damage = decayDamage(before.damageLoad + contribution.total, 1, cfg);

    // 恢复债：连续高强度日累积，休息日回落。
    final highLoad = consecutiveHighDays > 0 || band.isRisk;
    final recovery = (before.recoveryDebt + (highLoad ? 1.0 : -0.5))
        .clamp(0.0, 100.0)
        .toDouble();

    return StateVars(
      sleepDebtHours: sleepDebt.clamp(0.0, 72.0).toDouble(),
      damageLoad: damage,
      recoveryDebt: recovery,
      consistency: before.consistency,
      asOf: drafts.isEmpty ? before.asOf : drafts.first.dayKey,
    ).sanitized();
  }
}
