/// 能量账户日视图的组装。
///
/// 六层账本里的第 1–3 层（摄入、消耗、有效率）都在这里合成一个
/// [EnergyLedger]。缺数据时**不编数字**：摄入没记就是 0 并标记空缺，
/// 平衡区间会跨过零点显示"在误差范围内"。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/energy_ledger.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:exp_ledger/domain/science/energy.dart';

EnergyLedger buildEnergyLedger({
  required DayKey day,
  required UserProfile profile,
  required List<DraftEntry> drafts,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;

  var exerciseKcal = 0.0;
  var intakeKcal = 0.0;
  var nominalSets = 0.0;
  var effectiveSets = 0.0;
  var trainingMinutes = 0.0;
  var effectiveMinutes = 0.0;

  for (final d in drafts) {
    exerciseKcal += d.metrics['kcal'] ?? 0;
    intakeKcal += d.metrics['kcal_intake'] ?? 0;
    nominalSets += d.metrics['sets'] ?? 0;
    effectiveSets += d.metrics['effective_sets'] ?? 0;
    trainingMinutes += d.metrics['session_minutes'] ?? 0;
    trainingMinutes += d.metrics['minutes'] ?? 0;
    effectiveMinutes += d.metrics['effective_minutes'] ?? 0;
  }

  final breakdown = buildDailyBreakdown(
    profile: profile,
    intakeKcal: intakeKcal,
    exerciseKcal: exerciseKcal,
    activeDay: exerciseKcal > 200,
    cfg: c,
  );

  final balance = energyBalanceRange(
    intakeKcal: intakeKcal,
    expenditureKcal: breakdown.totalExpenditure,
  );

  // 训练效率 = 有效组 / 名义组（每一组有多少真的落在目标上）。
  final trainingEff =
      nominalSets <= 0 ? 0.0 : (effectiveSets / nominalSets).clampRange(0, 1);

  // 时间效率 = 有效练习时长 / 总投入时长。
  final timeEff = trainingMinutes <= 0
      ? 0.0
      : (effectiveMinutes <= 0
              ? (effectiveSets / 3.0).clampRange(0, 1)
              : (effectiveMinutes / trainingMinutes).clampRange(0, 1))
          .toDouble();

  return EnergyLedger(
    day: day,
    intakeKcal: intakeKcal,
    bmr: breakdown.bmr,
    tef: breakdown.tef,
    exercise: breakdown.exercise,
    epoc: breakdown.epoc,
    neat: breakdown.neat,
    trainingEfficiency: trainingEff,
    timeEfficiency: timeEff,
    balanceLow: balance.low,
    balanceHigh: balance.high,
  );
}

/// 摄入缺失时的说明（不吓人、不补数字）。
String intakeGapNote(EnergyLedger ledger) {
  if (ledger.intakeKcal > 0) return '';
  return '今天还没记饮食，摄入这一栏留空。缺失的数据不扣分，只标成空缺。';
}

/// 平衡区间的说明。用区间而不是单点，因为两边的误差都是真实存在的。
String balanceNote(EnergyLedger ledger) {
  if (ledger.intakeKcal <= 0) return '';
  final lo = ledger.balanceLow.round();
  final hi = ledger.balanceHigh.round();
  if (ledger.isInconclusive) {
    return '摄入与消耗的差额在 $lo ~ $hi kcal 之间，跨过零点，'
        '以现有精度判断不了盈余还是缺口。';
  }
  return ledger.isDeficit
      ? '估算缺口 $lo ~ $hi kcal（摄入低报与消耗高估的误差都已计入区间）。'
      : '估算盈余 $lo ~ $hi kcal（同样带误差区间，不是精确值）。';
}
