/// 能量代谢公式。
///
/// 公式出处与误差全部写在这里，UI 长按中间量直接读这份注释生成的来源卡
/// （见 core/config/science_citations.dart）。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';

/// 基础代谢率 —— Mifflin-St Jeor (1990, Am J Clin Nutr)。
///
/// BMR = 10·体重(kg) + 6.25·身高(cm) − 5·年龄 + (男 +5 / 女 −161)
/// 注意：对高体脂人群倾向高估，未做瘦体重修正；此为公式固有误差，不消除。
double bmrMifflinStJeor(UserProfile p) {
  final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
  final value = base + p.sex.bmrOffset;
  return value < 800 ? 800 : value;
}

/// 运动能量消耗 —— Ainsworth MET Compendium (2011)。
///
/// kcal = MET × 3.5 × 体重(kg) / 200 × 分钟
/// 个体差异约 ±20~30%，属于"公式级"而非"校准级"数据。
double metKcal({
  required double met,
  required double weightKg,
  required double minutes,
}) {
  if (minutes <= 0 || weightKg <= 0 || met <= 0) return 0;
  return met * 3.5 * weightKg / 200 * minutes;
}

/// 食物热效应 —— 混合膳食约占摄入的 8~12%，本项目固定取 10%（简化）。
double tefKcal(double intakeKcal, BalanceConfig cfg) =>
    intakeKcal <= 0 ? 0 : intakeKcal * cfg.tefFactor;

/// 运动后过量氧耗近似 —— 真正取值随强度/时长变化，区间 6~15%。
/// 本项目用线性因子（默认 8%），标注为启发式近似，不作为生理模型。
double epocKcal(double exerciseKcal, BalanceConfig cfg) =>
    exerciseKcal <= 0 ? 0 : exerciseKcal * cfg.epocFactor;

/// 非运动性活动产热近似 —— 用 FAO/WHO(2004) 的 PAL 系数反推。
///
/// NEAT ≈ BMR × (PAL − 1 − 运动占比)。误差大，仅用于把"久坐 vs 活跃"
/// 的差异画出来，不进入任何扣分判定。
double neatKcal({
  required double bmr,
  required bool activeDay,
  required double exerciseShareOfTdee,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  final pal = activeDay ? c.neatPalActive : c.neatPalSedentary;
  final share = exerciseShareOfTdee.clamp(0.0, 0.6).toDouble();
  final neat = bmr * (pal - 1 - share);
  return neat < 0 ? 0 : neat;
}

/// 每日总消耗的粗略拆解，六层账本的第 2 层用它。
class DailyEnergyBreakdown {
  const DailyEnergyBreakdown({
    required this.bmr,
    required this.tef,
    required this.exercise,
    required this.epoc,
    required this.neat,
  });

  final double bmr;
  final double tef;
  final double exercise;
  final double epoc;
  final double neat;

  double get totalExpenditure => bmr + tef + exercise + epoc + neat;

  double get activityShare => totalExpenditure <= 0
      ? 0
      : (exercise + epoc + neat) / totalExpenditure;
}

/// 组合一日消耗。
DailyEnergyBreakdown buildDailyBreakdown({
  required UserProfile profile,
  required double intakeKcal,
  required double exerciseKcal,
  required bool activeDay,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  final bmr = bmrMifflinStJeor(profile);
  final tef = tefKcal(intakeKcal, c);
  final epoc = epocKcal(exerciseKcal, c);
  final approxTdee = bmr + tef + exerciseKcal + epoc;
  final neat = neatKcal(
    bmr: bmr,
    activeDay: activeDay,
    exerciseShareOfTdee: approxTdee <= 0 ? 0 : exerciseKcal / approxTdee,
    cfg: c,
  );
  return DailyEnergyBreakdown(
    bmr: bmr,
    tef: tef,
    exercise: exerciseKcal,
    epoc: epoc,
    neat: neat,
  );
}

/// 摄入-消耗平衡：给区间而不是单点。误差来源是双边的（摄入低报 + 消耗估算）。
({double low, double high}) energyBalanceRange({
  required double intakeKcal,
  required double expenditureKcal,
  double intakeErrorRatio = 0.15,
  double expenditureErrorRatio = 0.12,
}) {
  final low = intakeKcal * (1 - intakeErrorRatio) - expenditureKcal * (1 + expenditureErrorRatio);
  final high = intakeKcal * (1 + intakeErrorRatio) - expenditureKcal * (1 - expenditureErrorRatio);
  return (low: low, high: high);
}
