/// 计划外事件的超额分流。
///
/// 判定顺序（不可交换，安全优先）：
///   1. 疲劳/缺觉状态下加练 → 风险，不先看 ACWR；
///   2. 会把你推入 ACWR 警戒/高风险 → 风险；
///   3. 同一肌群恢复间隔不足 → 风险；
///   4. 以上都不满足 → 有益超额，按 0.6 次幂递减计分。
///
/// 风险不等于"扣分"：超出安全上限的部分**不计加分**，转成损伤负荷。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/load_index.dart';

class OvershootDecision {
  const OvershootDecision({
    required this.beneficial,
    required this.creditedRatio,
    required this.excessRatio,
    required this.damageUnits,
    required this.reason,
    this.warnings = const [],
  });

  /// true = 有益超额（计分）；false = 过量风险（超出部分转损伤）。
  final bool beneficial;

  /// 计入加分的剂量比。风险时封顶 1.0（只有计划内那部分算）。
  final double creditedRatio;

  /// 超出计划的倍数（0 表示没超）。
  final double excessRatio;

  /// 转成损伤负荷的单位数。
  final double damageUnits;

  final String reason;
  final List<String> warnings;
}

OvershootDecision routeOvershoot({
  required double plannedDose,
  required double actualDose,
  required AcwrBand nextBand,
  required bool muscleRecovered,
  required bool fatigued,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  final actual = actualDose <= 0 ? 0.0 : actualDose;
  final planned = plannedDose <= 0 ? 0.0 : plannedDose;

  // 没有计划基线时，把"计划外"整体视为超额，但仍受安全上限约束。
  if (planned <= 0) {
    if (fatigued || nextBand.isRisk || !muscleRecovered) {
      return OvershootDecision(
        beneficial: false,
        creditedRatio: 0,
        excessRatio: 1,
        damageUnits: actual * c.overshootDamageFactor,
        reason: '没有计划基线，且当前恢复状态不支持额外负荷，这次不计分，转为损伤负荷。',
        warnings: const ['如果同时缺觉，建议今天到此为止。'],
      );
    }
    return OvershootDecision(
      beneficial: true,
      creditedRatio: marginalCredit(1.0),
      excessRatio: 1,
      damageUnits: 0,
      reason: '计划外完成，按边际递减计入。',
    );
  }

  final ratio = actual / planned;
  if (ratio <= 1.0) {
    return OvershootDecision(
      beneficial: true,
      creditedRatio: ratio,
      excessRatio: 0,
      damageUnits: 0,
      reason: '没有超出计划。',
    );
  }

  final excess = ratio - 1.0;
  final riskByBand = nextBand.isRisk;
  final riskByRecovery = !muscleRecovered;
  final riskByFatigue = fatigued;

  if (riskByFatigue || riskByBand || riskByRecovery) {
    final why = riskByFatigue
        ? '在疲劳状态下加量'
        : (riskByBand ? '会把负荷比推入警戒区（ACWR > 1.3）' : '同一肌群的恢复间隔不足 48 小时');
    return OvershootDecision(
      beneficial: false,
      creditedRatio: 1.0,
      excessRatio: excess,
      damageUnits: excess * actual * c.overshootDamageFactor,
      reason: '$why，超出的部分不计加分，转为损伤负荷。',
      warnings: [
        if (riskByBand) '接下来两天建议降载；若出现关节疼痛、心悸或异常乏力，请就医评估。',
        if (riskByFatigue) '疲劳叠加时，多练的那部分往往要用之后的几天还。',
      ],
    );
  }

  return OvershootDecision(
    beneficial: true,
    creditedRatio: marginalCredit(ratio),
    excessRatio: excess,
    damageUnits: 0,
    reason: '在个人适应范围内，超额部分按 0.6 次幂递减计入。',
  );
}

/// 超额后的计分倍率：1 + (ratio−1)^0.6。
double marginalCredit(double ratio) {
  if (ratio <= 1) return ratio <= 0 ? 0 : ratio;
  return 1 + powSafe(ratio - 1, 0.6);
}

/// 判定同一肌群是否已恢复（粗规则，仅用于分流）。
bool muscleRecovered({
  required int hoursSinceSameGroup,
  required String intensityZone,
}) {
  final required48 = intensityZone == '力量区' || intensityZone == '增肌区';
  return hoursSinceSameGroup >= (required48 ? 48 : 24);
}
