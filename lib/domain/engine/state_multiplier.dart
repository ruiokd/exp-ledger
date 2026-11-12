/// 状态乘数与置信度加权。
///
/// 作用顺序固定（写死顺序是为了让测试可断言）：
///   正向分 × 睡眠乘数 × 损伤乘数 × 恢复乘数 × 置信度权重
/// 负向**不乘**任何乘数——否则同一件事会被罚两次。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';

class Multipliers {
  const Multipliers({
    required this.sleep,
    required this.damage,
    required this.recovery,
  });

  final double sleep;
  final double damage;
  final double recovery;

  /// 组合乘数，下限 0.30——再糟也不至于把当天的努力归零。
  double get combined => (sleep * damage * recovery).clampRange(0.30, 1.0);

  Map<String, double> toMap() => {
        'sleep': sleep,
        'damage': damage,
        'recovery': recovery,
        'combined': combined,
      };
}

Multipliers multipliersFor(StateVars s, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  return Multipliers(
    sleep: c.sleepMultiplier(s.sleepDebtHours),
    damage: c.damageMultiplier(s.damageLoad),
    recovery: c.recoveryMultiplier(s.recoveryDebt),
  );
}

/// 置信度权重：calibrated 1.0 / formula 0.8 / self_report 0.6。
double confidenceWeightOf(Confidence c) => c.weight;

/// 一句话解释当前的折价，用于明细页（中性措辞，不说"你状态差"）。
String multiplierNote(Multipliers m, StateVars s) {
  final parts = <String>[];
  if (m.sleep < 0.999) {
    parts.add('睡眠负债 ${s.sleepDebtHours.toStringAsFixed(1)}h → 加分 ×${m.sleep.toStringAsFixed(2)}');
  }
  if (m.damage < 0.999) {
    parts.add('损伤负荷 ${s.damageLoad.toStringAsFixed(1)} → 加分 ×${m.damage.toStringAsFixed(2)}');
  }
  if (m.recovery < 0.999) {
    parts.add('恢复债 ${s.recoveryDebt.toStringAsFixed(1)} → 加分 ×${m.recovery.toStringAsFixed(2)}');
  }
  if (parts.isEmpty) return '';
  return '${parts.join('；')}。这是"同样的努力现在值多少分"的折算，不是对你的评价。';
}
