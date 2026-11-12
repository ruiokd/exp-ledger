/// 累积损伤负荷（damage_load）。
///
/// 这是一个**项目自定义的启发式指标**，不是任何医学量表。
/// 它的作用只有一个：把"练得多 ≠ 长得多"这件事画出来。
///
/// 三条来源：
///   1. ACWR 进入警戒/高风险；
///   2. 连续高强度日超过恢复间隔；
///   3. 睡眠负债叠加（恢复能力下降时，同样负荷造成的损伤更贵）。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/load_index.dart';

/// 一次结算对损伤负荷的贡献拆解。
class DamageContribution {
  const DamageContribution({
    required this.fromAcwr,
    required this.fromStreak,
    required this.fromSleep,
    required this.fromOvershoot,
    required this.fromInjury,
  });

  final double fromAcwr;
  final double fromStreak;
  final double fromSleep;
  final double fromOvershoot;
  final double fromInjury;

  double get total =>
      fromAcwr + fromStreak + fromSleep + fromOvershoot + fromInjury;

  bool get isZero => total <= 0;

  Map<String, double> toMap() => {
        'from_acwr': fromAcwr,
        'from_streak': fromStreak,
        'from_sleep': fromSleep,
        'from_overshoot': fromOvershoot,
        'from_injury': fromInjury,
      };
}

/// 计算当日的损伤负荷增量。
DamageContribution damageDelta({
  required AcwrBand band,
  required int consecutiveHighDays,
  required double sleepDebtHours,
  required double overshootUnits,
  required double injuryLoad,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;

  // 1. ACWR：警戒 0.8、高风险 2.0（单位：负荷点）
  final acwrPart = switch (band) {
    AcwrBand.warning => 0.8,
    AcwrBand.high => 2.0,
    _ => 0.0,
  };

  // 2. 连续高强度：超出 2 天开始计，第 3 天起每多一天成本递增。
  final streakExcess = (consecutiveHighDays - 2).clampRange(0, 10);
  final streakPart = streakExcess <= 0 ? 0.0 : 0.5 * streakExcess * streakExcess;

  // 3. 睡眠负债：每小时 0.15，最多 1.5。
  final sleepPart = (sleepDebtHours * 0.15).clampRange(0, 1.5);

  // 4. 超额训练转来的损伤（已由 overshoot 路由算好单位）。
  final overshootPart = overshootUnits.clampRange(0, 20);

  // 5. 受伤记录自带的负荷。
  final injuryPart = injuryLoad.clampRange(0, 6);

  return DamageContribution(
    fromAcwr: acwrPart * c.damageGain,
    fromStreak: streakPart * c.damageGain,
    fromSleep: sleepPart * c.damageGain,
    fromOvershoot: overshootPart,
    fromInjury: injuryPart,
  );
}

/// 损伤负荷的自然衰减。**必须慢于睡眠负债**——恢复比睡眠贵。
double decayDamage(double damage, int days, BalanceConfig? cfg) {
  final c = cfg ?? kDefaultConfig;
  if (days <= 0) return damage;
  var v = damage;
  for (var i = 0; i < days; i++) {
    v = v * (1 - c.damageDecayPerDay);
  }
  return v.clampRange(0, 100);
}

/// 损伤负荷的风险分级。用于图表上的风险区阴影深浅。
enum DamageTier { none, watch, elevated, marked }

DamageTier damageTier(double damage) {
  if (damage < 1) return DamageTier.none;
  if (damage < 4) return DamageTier.watch;
  if (damage < 8) return DamageTier.elevated;
  return DamageTier.marked;
}

/// "永久标记"判定：达到阈值后在图表上打不可磨灭的点。
///
/// 文案要求：明确"部分损伤可能长期不可逆" + 强烈建议就医 + 不做诊断。
bool needsPermanentMark(double damage) => damage >= 8;

String? permanentMarkMessage(double damage) {
  if (!needsPermanentMark(damage)) return null;
  return '累积负荷已达到需要标记的程度。部分结构性损伤（关节、肌腱、'
      '心血管与中枢神经相关）可能长期不可逆。建议尽快就医评估，'
      '本 App 只做记录，不做诊断。';
}

/// 损伤负荷对后续同等训练量的加分折价说明（中性措辞）。
String damageWeightNote(double damage, BalanceConfig? cfg) {
  final c = cfg ?? kDefaultConfig;
  final m = c.damageMultiplier(damage);
  if (m >= 0.999) return '';
  final pct = ((1 - m) * 100).round();
  return '当前损伤负荷会让同等训练的加分权重下降约 $pct%——恢复也是训练的一部分。';
}
