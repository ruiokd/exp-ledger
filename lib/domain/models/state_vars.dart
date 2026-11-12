import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// 四个全局状态变量。它们不产生分，但决定"同样努力值多少分"。
///
/// 设计意图：正向加分被状态乘数打折，负向扣分不乘乘数（否则等于
/// 对同一件事惩罚两次），但负向会写入这些变量——惩罚延后体现为
/// "成长变便宜了"，而不是"再扣一次"。
class StateVars {
  const StateVars({
    this.sleepDebtHours = 0,
    this.damageLoad = 0,
    this.recoveryDebt = 0,
    this.consistency = 0.5,
    this.asOf,
  });

  /// 睡眠负债（小时）。累计慢、回补也慢。
  final double sleepDebtHours;

  /// 累积损伤负荷（无量纲）。下降速度慢于睡眠负债——恢复更贵。
  final double damageLoad;

  /// 恢复债：连续高强度日、缺觉叠加产生的"未恢复"量。
  final double recoveryDebt;

  /// 一致性 0–1，最近 14 天的达标密度。
  final double consistency;

  final DayKey? asOf;

  static const StateVars zero = StateVars();

  StateVars copyWith({
    double? sleepDebtHours,
    double? damageLoad,
    double? recoveryDebt,
    double? consistency,
    DayKey? asOf,
  }) {
    return StateVars(
      sleepDebtHours: sleepDebtHours ?? this.sleepDebtHours,
      damageLoad: damageLoad ?? this.damageLoad,
      recoveryDebt: recoveryDebt ?? this.recoveryDebt,
      consistency: consistency ?? this.consistency,
      asOf: asOf ?? this.asOf,
    );
  }

  /// 跨夜自然衰减：睡一觉负债降 35%，损伤每天只降 6%。
  StateVars decayOvernight({
    required double sleepDebtDecayPerNight,
    required double damageDecayPerDay,
    required double sleptHours,
    required double sleepNeedHours,
  }) {
    // 睡够了才真正回补；睡不够时衰减很弱。
    final adequacy = (sleptHours / (sleepNeedHours <= 0 ? 7.5 : sleepNeedHours))
        .clampRange(0, 1.2);
    final debtFactor = 1 - sleepDebtDecayPerNight * adequacy;
    return StateVars(
      sleepDebtHours: (sleepDebtHours * debtFactor).clampRange(0, 72),
      damageLoad: (damageLoad * (1 - damageDecayPerDay)).clampRange(0, 100),
      recoveryDebt: (recoveryDebt * (1 - damageDecayPerDay * 1.4))
          .clampRange(0, 100),
      consistency: consistency,
      asOf: asOf,
    );
  }

  /// 完整性检查：任何一项越界都退回合理区间，避免脏数据污染曲线。
  StateVars sanitized() => StateVars(
        sleepDebtHours: sleepDebtHours.clampRange(0, 72),
        damageLoad: damageLoad.clampRange(0, 100),
        recoveryDebt: recoveryDebt.clampRange(0, 100),
        consistency: consistency.clampRange(0, 1),
        asOf: asOf,
      );

  Map<String, Object?> toMap() => {
        'sleep_debt_hours': sleepDebtHours,
        'damage_load': damageLoad,
        'recovery_debt': recoveryDebt,
        'consistency': consistency,
        'as_of': asOf?.iso,
      };
}
