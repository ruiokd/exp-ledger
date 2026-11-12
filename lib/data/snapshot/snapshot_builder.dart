/// 结算产物 → 能力快照 / 预测点。
///
/// 这一层只做"搬运 + 一个明确的换算"：
///   - 能力值：上一日 × 每日回退 + 当日正向 EXP × 折算率
///   - 等级：用 [applyExp] 复算 totalExp（`DaySettlement` 只留了等级与缓冲池，
///     累计经验要靠它倒推，否则第二天没法继续算）
///   - 预测：交给 `domain/forecast/ability_projection.dart`，这里不重写算法
///
/// 所有系数来自 [BalanceConfig]，这里没有裸数字。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/engine/level_curve.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/forecast/ability_projection.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';

class SnapshotBuilder {
  const SnapshotBuilder();

  /// 从"前一天快照 + 今日结算"推出今日快照。
  ///
  /// [previous] 为空表示这是第一天，五维从 [BalanceConfig.abilityBaseline] 起步。
  /// [daysWithData] 是近 N 天每个轴有记录的天数，用来算完整度。
  AbilitySnapshot build({
    required DayKey day,
    required DaySettlement settlement,
    AbilitySnapshot? previous,
    Map<String, int> daysWithData = const <String, int>{},
    BalanceConfig config = kDefaultConfig,
  }) {
    final abilities = <String, double>{};
    final completeness = <String, double>{};

    // 当日各轴的正向 EXP 合计。负向**不**扣能力值：能力是"练出来的存量"，
    // 熬夜不会让已经长出来的肌肉消失，但会让下一次训练变便宜（状态乘数）。
    final gain = <String, double>{};
    for (final e in settlement.positives) {
      if (e.exp <= 0) continue;
      gain[e.axis.name] = (gain[e.axis.name] ?? 0) + e.exp;
    }

    for (final axis in ProjectAxis.values) {
      final base = previous?.abilities[axis.name] ?? config.abilityBaseline;
      final decayed = base * (1 - config.abilityDecayPerDay);
      final added = (gain[axis.name] ?? 0) * config.abilityPerExp;
      abilities[axis.name] =
          (decayed + added).clampRange(0, config.abilityCap).toDouble();

      final window = config.completenessWindowDays <= 0
          ? 1.0
          : config.completenessWindowDays;
      completeness[axis.name] =
          ((daysWithData[axis.name] ?? 0) / window).clampRange(0, 1).toDouble();
    }

    final level = _rollLevel(previous, settlement, config);

    return AbilitySnapshot(
      day: day,
      abilities: abilities,
      completeness: completeness,
      totalExp: level.totalExp,
      level: level.level,
      buffer: level.buffer,
      status: settlement.status,
    );
  }

  /// 累计经验的唯一推法：拿前一天的三元组，加上今天的净经验。
  ///
  /// 直接 `totalExp + netExp` 是错的——负向经验先被缓冲池吸收，
  /// 只有超出部分才真的扣累计经验。这里复用领域层的 [applyExp]，
  /// 保证和流水线内部的等级判定完全同源。
  LevelState _rollLevel(
    AbilitySnapshot? previous,
    DaySettlement settlement,
    BalanceConfig config,
  ) {
    final before = LevelState(
      level: previous?.level ?? 0,
      totalExp: previous?.totalExp ?? 0,
      buffer: previous?.buffer ?? 0,
    );
    if (settlement.status == SettlementStatus.paused) {
      // 暂停结算：一分不加也不扣，状态原地不动。
      return before;
    }
    return applyExp(before, settlement.netExp, config);
  }

  /// 生成"今天 → 未来"的预测。
  ///
  /// 每条线都带自己的置信带；只画一条会变宿命论，只画上行是鸡汤。
  Map<ProjectAxis, List<ForecastPoint>> buildForecast({
    required DayKey today,
    required AbilitySnapshot snapshot,
    required DaySettlement settlement,
    required double recentDailyExp,
    BalanceConfig config = kDefaultConfig,
  }) {
    final horizon = config.forecastHorizonDays.toInt();
    final step = config.forecastStepDays.toInt() < 1
        ? 1
        : config.forecastStepDays.toInt();

    final out = <ProjectAxis, List<ForecastPoint>>{};
    for (final axis in ProjectAxis.values) {
      final input = ProjectionInput(
        today: today,
        currentAbility: snapshot.abilityOf(axis.name),
        axis: axis,
        state: settlement.stateAfter,
        recentDailyExp: recentDailyExp,
        horizonDays: horizon,
        stepDays: step,
        config: config,
        isInterruption: settlement.isInterruption,
      );
      out[axis] = project(input);
    }
    return out;
  }

  /// 只有"今天"这一点的实际值（历史日每天写一条，供主图折线用）。
  Map<ProjectAxis, List<ForecastPoint>> actualOnly(AbilitySnapshot snapshot) {
    final out = <ProjectAxis, List<ForecastPoint>>{};
    for (final axis in ProjectAxis.values) {
      final v = snapshot.abilityOf(axis.name);
      out[axis] = <ForecastPoint>[
        ForecastPoint(
          day: snapshot.day,
          maintain: v,
          correct: v,
          low: v,
          high: v,
          confidence: 1,
          isProjection: false,
        ),
      ];
    }
    return out;
  }
}
