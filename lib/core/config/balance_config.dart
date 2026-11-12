import 'package:exp_ledger/core/util/num_ext.dart';

/// 全部数值系数的唯一来源。
///
/// 铁律：任何算法文件里不允许出现裸数字系数，必须从这里取。
/// 这样"数值实验室"改一个字段，整条流水线重算后曲线立刻变化。
class BalanceConfig {
  const BalanceConfig({
    // ---- 能量与代谢 ----
    this.tefFactor = 0.10,
    this.epocFactor = 0.08,
    this.neatPalSedentary = 1.40,
    this.neatPalActive = 1.70,
    this.metResistanceModerate = 5.0,
    this.metResistanceVigorous = 6.0,
    this.metCardioFactor = 1.0,
    // ---- 训练剂量 ----
    this.restSecondsPerSet = 90.0,
    this.secondsPerRep = 3.5,
    this.minEffectiveSetFraction = 0.5,
    this.rirFullThreshold = 1.0,
    // ---- 记忆 ----
    this.memoryStrengthBase = 2.6,
    this.memoryActiveRecallBoost = 1.55,
    this.memoryReviewBoost = 1.25,
    this.memoryCoverageThreshold = 0.98,
    // ---- 加减分 ----
    this.expPerPoint = 0.5,
    this.partialDoseExponent = 0.8,
    this.qualityBonusCap = 0.40,
    this.qualityWeight = 1.0,
    this.efficiencyWeight = 0.25,
    this.efficiencyBonusCap = 0.15,
    this.overshootExponent = 0.6,
    this.overshootDamageFactor = 0.35,
    this.damageGain = 1.0,
    this.acwrLowRiskMin = 0.8,
    this.acwrLowRiskMax = 1.3,
    this.acwrWarningMax = 1.5,
    // ---- 负向曲线 ----
    this.negK1 = 0.0040,
    this.negK2 = 0.0012,
    this.negK3 = 0.000040,
    this.negLinearZoneMinutes = 30.0,
    this.negAccelZoneMinutes = 120.0,
    this.negScaleExp = 3.0,
    // ---- 状态变量 ----
    this.sleepDebtPenaltyPerHour = 0.05,
    this.sleepDebtPenaltyCap = 0.35,
    this.damagePenaltyPerLoad = 0.06,
    this.damagePenaltyCap = 0.50,
    this.recoveryPenaltyPerUnit = 0.04,
    this.recoveryPenaltyCap = 0.20,
    this.sleepDebtDecayPerNight = 0.35,
    this.damageDecayPerDay = 0.06,
    // ---- 等级 ----
    this.levelBaseExp = 100.0,
    this.levelExponent = 1.6,
    this.levelBufferRatio = 0.35,
    // ---- 项目权重（归一化到 0–100 后乘权重转 EXP）----
    this.weightStrength = 1.00,
    this.weightCardio = 0.90,
    this.weightMemory = 0.95,
    this.weightWriting = 0.70,
    this.weightMind = 0.55,
    this.weightSleep = 0.85,
    this.weightNutrition = 0.60,
    this.weightRestraint = 0.75,
    // ---- 快照 / 预测 / 记忆（数据层重算用）----
    this.abilityBaseline = 40.0,
    this.abilityCap = 120.0,
    this.abilityDecayPerDay = 0.004,
    this.abilityPerExp = 0.25,
    this.completenessWindowDays = 28.0,
    this.forecastHorizonDays = 90.0,
    this.forecastStepDays = 3.0,
    this.srpeDefaultRpe = 6.0,
    this.memoryReviewBaseDays = 1.0,
    this.memoryReviewGrowth = 2.3,
    this.memoryReviewMaxDays = 180.0,
    // ---- 采集体检 ----
    this.defaultSleepNeedHours = 7.5,
    this.defaultSleepLineHour = 0,
    this.defaultSleepLineMinute = 20,
  });

  // ---- 能量与代谢 ----
  final double tefFactor;
  final double epocFactor;
  final double neatPalSedentary;
  final double neatPalActive;
  final double metResistanceModerate;
  final double metResistanceVigorous;
  final double metCardioFactor;

  // ---- 训练剂量 ----
  final double restSecondsPerSet;
  final double secondsPerRep;
  final double minEffectiveSetFraction;
  final double rirFullThreshold;

  // ---- 记忆 ----
  final double memoryStrengthBase;
  final double memoryActiveRecallBoost;
  final double memoryReviewBoost;
  final double memoryCoverageThreshold;

  // ---- 加减分 ----
  /// 1 点"当日有效分"折算多少 EXP。0.5 意味着满分日约 50 EXP 量级。
  final double expPerPoint;

  /// 未达标剂量的部分计入指数（<1 表示"差一点也有分"）。
  final double partialDoseExponent;

  final double qualityBonusCap;
  final double qualityWeight;
  final double efficiencyWeight;

  /// 极简加分的硬上限（相对基础分的比例）。
  final double efficiencyBonusCap;

  final double overshootExponent;
  final double overshootDamageFactor;

  /// 风险事件 → 损伤负荷的换算增益。
  final double damageGain;

  final double acwrLowRiskMin;
  final double acwrLowRiskMax;
  final double acwrWarningMax;

  // ---- 负向曲线 ----
  final double negK1;
  final double negK2;
  final double negK3;
  final double negLinearZoneMinutes;
  final double negAccelZoneMinutes;
  final double negScaleExp;

  // ---- 状态变量 ----
  final double sleepDebtPenaltyPerHour;
  final double sleepDebtPenaltyCap;
  final double damagePenaltyPerLoad;
  final double damagePenaltyCap;
  final double recoveryPenaltyPerUnit;
  final double recoveryPenaltyCap;
  final double sleepDebtDecayPerNight;
  final double damageDecayPerDay;

  // ---- 等级 ----
  final double levelBaseExp;
  final double levelExponent;
  final double levelBufferRatio;

  // ---- 权重 ----
  final double weightStrength;
  final double weightCardio;
  final double weightMemory;
  final double weightWriting;
  final double weightMind;
  final double weightSleep;
  final double weightNutrition;
  final double weightRestraint;

  // ---- 采集 ----
  final double defaultSleepNeedHours;
  final int defaultSleepLineHour;
  final int defaultSleepLineMinute;

  // ---- 快照 / 预测 / 记忆（数据层重算用）----

  /// 五维能力的初始基线（0–100 口径）。
  final double abilityBaseline;

  /// 能力值上限。允许超过 100，因为"上限 100"会让人一眼看出是刻度而非估计。
  final double abilityCap;

  /// 能力的每日自然回退比例（不用就缓慢回落，但不像停训那样陡）。
  final double abilityDecayPerDay;

  /// 每 1 点正向 EXP 折算多少能力值。
  final double abilityPerExp;

  /// 完整度统计窗口（天）。窗口内每天都记录 → 完整度 1。
  final double completenessWindowDays;

  /// 预测时长（天）与打点步长（天）。存成 double 是为了能被
  /// `config_override` 的数值实验室统一覆盖（覆盖表只有 REAL 列）。
  final double forecastHorizonDays;
  final double forecastStepDays;

  /// 记录里没写 RPE 也没写 RIR 时，按中等强度估。
  /// 显式设成系数而非常量，是因为它直接影响 ACWR 与后续负荷判定。
  final double srpeDefaultRpe;

  /// 记忆复习间隔：base × growth^(复习次数)，上限 max。
  final double memoryReviewBaseDays;
  final double memoryReviewGrowth;
  final double memoryReviewMaxDays;

  // ---------------------------------------------------------------- 曲线派生

  /// 负向"剂量 → 扣分量"曲线（未乘 negScaleExp）。
  /// 分段连续：
  ///   d ≤ d0        → k1·d                       （轻微越界，近似线性小额）
  ///   d0 < d ≤ d1   → + k2·(d−d0)^1.5            （加速区）
  ///   d > d1        → + k3·(d−d1)^2              （深度越界，陡增）
  /// 单调不减，一阶导单调不减——单测断言此性质。
  double negativeDoseCurve(double minutes) {
    final d = minutes.clampRange(0, 1e6);
    final d0 = negLinearZoneMinutes;
    final d1 = negAccelZoneMinutes;
    final linear = negK1 * (d < d0 ? d : d0);
    final accel = d > d0 ? negK2 * powSafe(d - d0, 1.5) : 0.0;
    final deep = d > d1 ? negK3 * powSafe(d - d1, 2) : 0.0;
    return linear + accel + deep;
  }

  /// 负向扣分对应的 EXP（负值）。
  double negativeDoseExp(double minutes) => -negativeDoseCurve(minutes) * negScaleExp;

  /// 睡眠负债对**次日正向加分**的折价乘数。
  double sleepMultiplier(double debtHours) =>
      1 - (debtHours * sleepDebtPenaltyPerHour).clampRange(0, sleepDebtPenaltyCap);

  /// 累积损伤负荷对加分权重的折价乘数。
  double damageMultiplier(double damageLoad) =>
      1 - (damageLoad * damagePenaltyPerLoad).clampRange(0, damagePenaltyCap);

  /// 恢复债对加分的折价乘数。
  double recoveryMultiplier(double recoveryDebt) =>
      1 -
      (recoveryDebt * recoveryPenaltyPerUnit)
          .clampRange(0, recoveryPenaltyCap);

  /// 等级 n 的累计 EXP 门槛：100 × n^1.6（本项目自定的游戏化曲线，非科学公式）。
  double levelThreshold(int level) =>
      levelBaseExp * powSafe(level.toDouble(), levelExponent);

  /// 由累计 EXP 反推等级（允许负 EXP → 0 级）。
  int levelFor(double totalExp) {
    if (totalExp <= 0) return 0;
    var n = 0;
    while (levelThreshold(n + 1) <= totalExp && n < 999) {
      n++;
    }
    return n;
  }

  // ---------------------------------------------------------------- copyWith

  BalanceConfig copyWith({
    double? tefFactor,
    double? epocFactor,
    double? neatPalSedentary,
    double? neatPalActive,
    double? metResistanceModerate,
    double? metResistanceVigorous,
    double? metCardioFactor,
    double? restSecondsPerSet,
    double? secondsPerRep,
    double? minEffectiveSetFraction,
    double? rirFullThreshold,
    double? memoryStrengthBase,
    double? memoryActiveRecallBoost,
    double? memoryReviewBoost,
    double? memoryCoverageThreshold,
    double? qualityBonusCap,
    double? qualityWeight,
    double? efficiencyWeight,
    double? efficiencyBonusCap,
    double? expPerPoint,
    double? partialDoseExponent,
    double? damageGain,
    double? overshootExponent,
    double? overshootDamageFactor,
    double? acwrLowRiskMin,
    double? acwrLowRiskMax,
    double? acwrWarningMax,
    double? negK1,
    double? negK2,
    double? negK3,
    double? negLinearZoneMinutes,
    double? negAccelZoneMinutes,
    double? negScaleExp,
    double? sleepDebtPenaltyPerHour,
    double? sleepDebtPenaltyCap,
    double? damagePenaltyPerLoad,
    double? damagePenaltyCap,
    double? recoveryPenaltyPerUnit,
    double? recoveryPenaltyCap,
    double? sleepDebtDecayPerNight,
    double? damageDecayPerDay,
    double? levelBaseExp,
    double? levelExponent,
    double? levelBufferRatio,
    double? weightStrength,
    double? weightCardio,
    double? weightMemory,
    double? weightWriting,
    double? weightMind,
    double? weightSleep,
    double? weightNutrition,
    double? weightRestraint,
    double? memoryReviewMaxDays,
    double? abilityBaseline,
    double? abilityCap,
    double? abilityDecayPerDay,
    double? abilityPerExp,
    double? completenessWindowDays,
    double? forecastHorizonDays,
    double? forecastStepDays,
    double? srpeDefaultRpe,
    double? memoryReviewBaseDays,
    double? memoryReviewGrowth,
    double? defaultSleepNeedHours,
    int? defaultSleepLineHour,
    int? defaultSleepLineMinute,
  }) {
    return BalanceConfig(
      tefFactor: tefFactor ?? this.tefFactor,
      epocFactor: epocFactor ?? this.epocFactor,
      neatPalSedentary: neatPalSedentary ?? this.neatPalSedentary,
      neatPalActive: neatPalActive ?? this.neatPalActive,
      metResistanceModerate:
          metResistanceModerate ?? this.metResistanceModerate,
      metResistanceVigorous:
          metResistanceVigorous ?? this.metResistanceVigorous,
      metCardioFactor: metCardioFactor ?? this.metCardioFactor,
      restSecondsPerSet: restSecondsPerSet ?? this.restSecondsPerSet,
      secondsPerRep: secondsPerRep ?? this.secondsPerRep,
      minEffectiveSetFraction:
          minEffectiveSetFraction ?? this.minEffectiveSetFraction,
      rirFullThreshold: rirFullThreshold ?? this.rirFullThreshold,
      memoryStrengthBase: memoryStrengthBase ?? this.memoryStrengthBase,
      memoryActiveRecallBoost:
          memoryActiveRecallBoost ?? this.memoryActiveRecallBoost,
      memoryReviewBoost: memoryReviewBoost ?? this.memoryReviewBoost,
      memoryCoverageThreshold:
          memoryCoverageThreshold ?? this.memoryCoverageThreshold,
      qualityBonusCap: qualityBonusCap ?? this.qualityBonusCap,
      qualityWeight: qualityWeight ?? this.qualityWeight,
      efficiencyWeight: efficiencyWeight ?? this.efficiencyWeight,
      efficiencyBonusCap: efficiencyBonusCap ?? this.efficiencyBonusCap,
      expPerPoint: expPerPoint ?? this.expPerPoint,
      partialDoseExponent: partialDoseExponent ?? this.partialDoseExponent,
      damageGain: damageGain ?? this.damageGain,
      overshootExponent: overshootExponent ?? this.overshootExponent,
      overshootDamageFactor:
          overshootDamageFactor ?? this.overshootDamageFactor,
      acwrLowRiskMin: acwrLowRiskMin ?? this.acwrLowRiskMin,
      acwrLowRiskMax: acwrLowRiskMax ?? this.acwrLowRiskMax,
      acwrWarningMax: acwrWarningMax ?? this.acwrWarningMax,
      negK1: negK1 ?? this.negK1,
      negK2: negK2 ?? this.negK2,
      negK3: negK3 ?? this.negK3,
      negLinearZoneMinutes: negLinearZoneMinutes ?? this.negLinearZoneMinutes,
      negAccelZoneMinutes: negAccelZoneMinutes ?? this.negAccelZoneMinutes,
      negScaleExp: negScaleExp ?? this.negScaleExp,
      sleepDebtPenaltyPerHour:
          sleepDebtPenaltyPerHour ?? this.sleepDebtPenaltyPerHour,
      sleepDebtPenaltyCap: sleepDebtPenaltyCap ?? this.sleepDebtPenaltyCap,
      damagePenaltyPerLoad: damagePenaltyPerLoad ?? this.damagePenaltyPerLoad,
      damagePenaltyCap: damagePenaltyCap ?? this.damagePenaltyCap,
      recoveryPenaltyPerUnit:
          recoveryPenaltyPerUnit ?? this.recoveryPenaltyPerUnit,
      recoveryPenaltyCap: recoveryPenaltyCap ?? this.recoveryPenaltyCap,
      sleepDebtDecayPerNight:
          sleepDebtDecayPerNight ?? this.sleepDebtDecayPerNight,
      damageDecayPerDay: damageDecayPerDay ?? this.damageDecayPerDay,
      levelBaseExp: levelBaseExp ?? this.levelBaseExp,
      levelExponent: levelExponent ?? this.levelExponent,
      levelBufferRatio: levelBufferRatio ?? this.levelBufferRatio,
      weightStrength: weightStrength ?? this.weightStrength,
      weightCardio: weightCardio ?? this.weightCardio,
      weightMemory: weightMemory ?? this.weightMemory,
      weightWriting: weightWriting ?? this.weightWriting,
      weightMind: weightMind ?? this.weightMind,
      weightSleep: weightSleep ?? this.weightSleep,
      weightNutrition: weightNutrition ?? this.weightNutrition,
      weightRestraint: weightRestraint ?? this.weightRestraint,
      memoryReviewMaxDays: memoryReviewMaxDays ?? this.memoryReviewMaxDays,
      abilityBaseline: abilityBaseline ?? this.abilityBaseline,
      abilityCap: abilityCap ?? this.abilityCap,
      abilityDecayPerDay: abilityDecayPerDay ?? this.abilityDecayPerDay,
      abilityPerExp: abilityPerExp ?? this.abilityPerExp,
      completenessWindowDays:
          completenessWindowDays ?? this.completenessWindowDays,
      forecastHorizonDays: forecastHorizonDays ?? this.forecastHorizonDays,
      forecastStepDays: forecastStepDays ?? this.forecastStepDays,
      srpeDefaultRpe: srpeDefaultRpe ?? this.srpeDefaultRpe,
      memoryReviewBaseDays: memoryReviewBaseDays ?? this.memoryReviewBaseDays,
      memoryReviewGrowth: memoryReviewGrowth ?? this.memoryReviewGrowth,
      defaultSleepNeedHours: defaultSleepNeedHours ?? this.defaultSleepNeedHours,
      defaultSleepLineHour: defaultSleepLineHour ?? this.defaultSleepLineHour,
      defaultSleepLineMinute:
          defaultSleepLineMinute ?? this.defaultSleepLineMinute,
    );
  }

  /// 序列化为可落库的扁平 map（数值实验室的覆盖值也用它）。
  Map<String, double> toMap() => {
        'tefFactor': tefFactor,
        'epocFactor': epocFactor,
        'metResistanceModerate': metResistanceModerate,
        'metResistanceVigorous': metResistanceVigorous,
        'restSecondsPerSet': restSecondsPerSet,
        'secondsPerRep': secondsPerRep,
        'memoryStrengthBase': memoryStrengthBase,
        'memoryActiveRecallBoost': memoryActiveRecallBoost,
        'qualityBonusCap': qualityBonusCap,
        'qualityWeight': qualityWeight,
        'efficiencyWeight': efficiencyWeight,
        'efficiencyBonusCap': efficiencyBonusCap,
        'expPerPoint': expPerPoint,
        'partialDoseExponent': partialDoseExponent,
        'damageGain': damageGain,
        'overshootExponent': overshootExponent,
        'overshootDamageFactor': overshootDamageFactor,
        'acwrLowRiskMin': acwrLowRiskMin,
        'acwrLowRiskMax': acwrLowRiskMax,
        'acwrWarningMax': acwrWarningMax,
        'negK1': negK1,
        'negK2': negK2,
        'negK3': negK3,
        'negLinearZoneMinutes': negLinearZoneMinutes,
        'negAccelZoneMinutes': negAccelZoneMinutes,
        'negScaleExp': negScaleExp,
        'sleepDebtPenaltyPerHour': sleepDebtPenaltyPerHour,
        'sleepDebtPenaltyCap': sleepDebtPenaltyCap,
        'damagePenaltyPerLoad': damagePenaltyPerLoad,
        'damagePenaltyCap': damagePenaltyCap,
        'recoveryPenaltyPerUnit': recoveryPenaltyPerUnit,
        'recoveryPenaltyCap': recoveryPenaltyCap,
        'levelBaseExp': levelBaseExp,
        'levelExponent': levelExponent,
        'levelBufferRatio': levelBufferRatio,
        'abilityBaseline': abilityBaseline,
        'abilityCap': abilityCap,
        'abilityDecayPerDay': abilityDecayPerDay,
        'abilityPerExp': abilityPerExp,
        'completenessWindowDays': completenessWindowDays,
        'forecastHorizonDays': forecastHorizonDays,
        'forecastStepDays': forecastStepDays,
        'srpeDefaultRpe': srpeDefaultRpe,
        'memoryReviewBaseDays': memoryReviewBaseDays,
        'memoryReviewGrowth': memoryReviewGrowth,
        'memoryReviewMaxDays': memoryReviewMaxDays,
        'memoryReviewBoost': memoryReviewBoost,
        'memoryCoverageThreshold': memoryCoverageThreshold,
        'minEffectiveSetFraction': minEffectiveSetFraction,
        'rirFullThreshold': rirFullThreshold,
        'neatPalSedentary': neatPalSedentary,
        'neatPalActive': neatPalActive,
        'metCardioFactor': metCardioFactor,
        'weightStrength': weightStrength,
        'weightCardio': weightCardio,
        'weightMemory': weightMemory,
        'weightWriting': weightWriting,
        'weightMind': weightMind,
        'weightSleep': weightSleep,
        'weightNutrition': weightNutrition,
        'weightRestraint': weightRestraint,
        'sleepDebtDecayPerNight': sleepDebtDecayPerNight,
        'damageDecayPerDay': damageDecayPerDay,
      };

  /// 从覆盖值构造（缺项保持当前值）。用 copyWith 串起来，
  /// 保证加新字段时这里不会漏——漏了就会被单测抓到。
  BalanceConfig withOverrides(Map<String, double> o) {
    return copyWith(
      tefFactor: o['tefFactor'],
      epocFactor: o['epocFactor'],
      metResistanceModerate: o['metResistanceModerate'],
      metResistanceVigorous: o['metResistanceVigorous'],
      restSecondsPerSet: o['restSecondsPerSet'],
      secondsPerRep: o['secondsPerRep'],
      memoryStrengthBase: o['memoryStrengthBase'],
      memoryActiveRecallBoost: o['memoryActiveRecallBoost'],
      qualityBonusCap: o['qualityBonusCap'],
      qualityWeight: o['qualityWeight'],
      efficiencyWeight: o['efficiencyWeight'],
      efficiencyBonusCap: o['efficiencyBonusCap'],
      expPerPoint: o['expPerPoint'],
      partialDoseExponent: o['partialDoseExponent'],
      damageGain: o['damageGain'],
      overshootExponent: o['overshootExponent'],
      overshootDamageFactor: o['overshootDamageFactor'],
      acwrLowRiskMin: o['acwrLowRiskMin'],
      acwrLowRiskMax: o['acwrLowRiskMax'],
      acwrWarningMax: o['acwrWarningMax'],
      negK1: o['negK1'],
      negK2: o['negK2'],
      negK3: o['negK3'],
      negLinearZoneMinutes: o['negLinearZoneMinutes'],
      negAccelZoneMinutes: o['negAccelZoneMinutes'],
      negScaleExp: o['negScaleExp'],
      sleepDebtPenaltyPerHour: o['sleepDebtPenaltyPerHour'],
      sleepDebtPenaltyCap: o['sleepDebtPenaltyCap'],
      damagePenaltyPerLoad: o['damagePenaltyPerLoad'],
      damagePenaltyCap: o['damagePenaltyCap'],
      recoveryPenaltyPerUnit: o['recoveryPenaltyPerUnit'],
      recoveryPenaltyCap: o['recoveryPenaltyCap'],
      levelBaseExp: o['levelBaseExp'],
      levelExponent: o['levelExponent'],
      levelBufferRatio: o['levelBufferRatio'],
      abilityBaseline: o['abilityBaseline'],
      abilityCap: o['abilityCap'],
      abilityDecayPerDay: o['abilityDecayPerDay'],
      abilityPerExp: o['abilityPerExp'],
      completenessWindowDays: o['completenessWindowDays'],
      forecastHorizonDays: o['forecastHorizonDays'],
      forecastStepDays: o['forecastStepDays'],
      srpeDefaultRpe: o['srpeDefaultRpe'],
      memoryReviewBaseDays: o['memoryReviewBaseDays'],
      memoryReviewGrowth: o['memoryReviewGrowth'],
      memoryReviewMaxDays: o['memoryReviewMaxDays'],
      memoryReviewBoost: o['memoryReviewBoost'],
      memoryCoverageThreshold: o['memoryCoverageThreshold'],
      minEffectiveSetFraction: o['minEffectiveSetFraction'],
      rirFullThreshold: o['rirFullThreshold'],
      neatPalSedentary: o['neatPalSedentary'],
      neatPalActive: o['neatPalActive'],
      metCardioFactor: o['metCardioFactor'],
      weightStrength: o['weightStrength'],
      weightCardio: o['weightCardio'],
      weightMemory: o['weightMemory'],
      weightWriting: o['weightWriting'],
      weightMind: o['weightMind'],
      weightSleep: o['weightSleep'],
      weightNutrition: o['weightNutrition'],
      weightRestraint: o['weightRestraint'],
      sleepDebtDecayPerNight: o['sleepDebtDecayPerNight'],
      damageDecayPerDay: o['damageDecayPerDay'],
    );
  }
}

/// 默认配置单例。
const BalanceConfig kDefaultConfig = BalanceConfig();
