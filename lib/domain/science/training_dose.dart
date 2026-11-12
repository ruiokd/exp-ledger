/// 抗阻训练剂量与强度换算。
///
/// 这里的每一个系数都是"训练量"的经验近似（volume load 是健身科学里
/// 常用的粗略指标，不是精确的肌纤维刺激量）。凡是近似都在命名上带
/// `approx` 或注释里写明，禁止在 UI 里说成"精确刺激量"。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// RIR（Reps In Reserve，还能做几次）→ 强度系数。
///
/// 越接近力竭，单组刺激越高，但恢复成本也越高，所以系数封顶 1.0 而不是
/// 线性放大。RIR 是主观自评，属 confidence=selfReport。
double intensityFactorFromRir(int rir, BalanceConfig? cfg) {
  final c = cfg ?? kDefaultConfig;
  if (rir <= c.rirFullThreshold) return 1.0;
  if (rir <= 2) return 0.9;
  if (rir <= 4) return 0.8;
  if (rir <= 6) return 0.65;
  return 0.55;
}

/// RPE(0–10) → RIR。常用近似：RIR ≈ 10 − RPE。
int rirFromRpe(double rpe) => (10 - rpe).round().clamp(0, 10).toInt();

/// 动作质量/代偿惩罚。自评代偿意味着"这一组的名义次数没全落在目标肌群上"。
double compensationFactor(String compensation) => switch (compensation) {
      'none' => 1.0,
      'mild' => 0.85,
      'severe' => 0.65,
      _ => 1.0,
    };

/// 单次动作占用的秒数（含离心控制），默认 3.5 秒/次。
double repSeconds(double secondsPerRep) => secondsPerRep;

/// 估算一组训练占用的总时长（含组间休息），用于 MET 能量换算。
///
/// 这是明显简化：真实训练还有换片、走神、器械排队。因此只用于"量级正确"，
/// 不作为精确能耗。
double estimateSessionMinutes({
  required int sets,
  required int reps,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  if (sets <= 0 || reps <= 0) return 0;
  final workSeconds = reps * c.secondsPerRep;
  // 每组都配一段休息（最后一组算作收尾），避免"1 组"算出 0 分钟能耗。
  final total = sets * (workSeconds + c.restSecondsPerSet);
  return total / 60;
}

/// 总容量（volume load）= 组数 × 次数 × 重量。自重动作重量记 0。
double volumeLoad({
  required int sets,
  required int reps,
  required double weightKg,
}) =>
    sets <= 0 || reps <= 0 || weightKg <= 0 ? 0 : sets * reps * weightKg;

/// "有效组"计数：名义组数经次数折算，得到接近等价的"标准组"。
///
/// repFactor 以 8 次/组为基准折算，并上下夹紧，避免"100 次×1 组"
/// 被误算成 12.5 个标准组。
double effectiveSets({
  required int sets,
  required int reps,
  required double intensityFactor,
  required double compensation,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  if (sets <= 0 || reps <= 0) return 0;
  final repFactor = (reps / 8.0).clampRange(0.5, 1.25);
  final raw = sets * repFactor * intensityFactor * compensation;
  // 有效组永不小于名义组的一半，否则用户会觉得"我练了但系统当我没练"。
  return raw < sets * c.minEffectiveSetFraction
      ? sets * c.minEffectiveSetFraction
      : raw;
}

/// Epley 公式估算 1RM：1RM ≈ w × (1 + reps/30)。
///
/// 出处：Epley, 1985。reps > 12 时误差显著放大，本项目 >12 次直接返回 null，
/// 交给校准测试（真实 1RM 测试）来填这个位置。
double? epleyOneRm({required double weight, required int reps}) {
  if (weight <= 0 || reps <= 0) return null;
  if (reps > 12) return null;
  return weight * (1 + reps / 30);
}

/// 相对强度：这一组的重量占 1RM 的比例。用于判断"这是力量组还是耐力组"。
double? relativeIntensity({required double weight, double? oneRm}) {
  if (oneRm == null || oneRm <= 0 || weight <= 0) return null;
  return (weight / oneRm).clampRange(0, 1.5);
}

/// 训练类型标签，仅用于文案，不参与算分。
String trainingZoneLabel(double? relIntensity) {
  if (relIntensity == null) return '强度未知';
  if (relIntensity >= 0.85) return '力量区';
  if (relIntensity >= 0.67) return '增肌区';
  if (relIntensity >= 0.5) return '耐力-增肌区';
  return '耐力区';
}
