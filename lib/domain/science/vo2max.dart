/// 心肺能力估算。
///
/// 两条路径都标注了出处与误差，UI 上必须带上"估算"二字：
///   1. Uth–Sørensen et al., 2004：VO2max ≈ 15 × HRmax / HRrest
///      （依赖静息心率测量质量，误差 ±10~15%）
///   2. Cooper 12 分钟跑（1968）：VO2max ≈ (距离米 − 504.9) / 44.73
///
/// 最大心率用 Tanaka et al., 2001 的 208 − 0.7×年龄，
/// 比旧的 220−年龄 在新版研究中更稳，但仍是群体回归值。
library;

import 'package:exp_ledger/core/util/num_ext.dart';

/// Tanaka 最大心率估算。
double maxHeartRateTanaka(int age) =>
    208 - 0.7 * age.clamp(10, 100).toDouble();

/// Uth–Sørensen 法。静息心率过低（<35）或为 0 时返回 null。
double? vo2MaxFromHeartRate({required int age, required int restingHr}) {
  if (restingHr < 35 || restingHr > 110) return null;
  final hrmax = maxHeartRateTanaka(age);
  return 15 * hrmax / restingHr;
}

/// Cooper 12 分钟跑。
double? vo2MaxFromCooper({required double distanceMeters}) {
  if (distanceMeters <= 500) return null;
  return (distanceMeters - 504.9) / 44.73;
}

/// 心肺刺激量（MET·分钟）→ 相对 VO2max 变化的启发式映射。
///
/// 这是**启发式**：真实 VO2max 变化受强度分布、个体反应、遗传影响很大，
/// 不能由 MET·分钟线性推出。这里只把它当作"这一周给了多少心肺刺激"的相对量，
/// 用于画趋势，不用于宣称"你的 VO2max 涨了 3 点"。
double cardioStimulusIndex(double metMinutes) =>
    metMinutes <= 0 ? 0 : 100 * (1 - 1 / (1 + metMinutes / 600));

/// 五公里成绩与 VO2max 的粗略对应（Daniels 跑步公式的简化查表近似）。
double? vo2MaxFromFiveK({required int seconds}) {
  if (seconds <= 0) return null;
  final minutes = seconds / 60.0;
  final velocity = 5000 / minutes; // 米/分
  // Daniels & Gilbert 的氧耗曲线简化式
  final vo2 = -4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity;
  return vo2.clampRange(10, 90);
}

/// 心肺能力的展示值（0–100），由 VO2max 映射。
double cardioAbilityValue(double vo2max) =>
    ((vo2max - 20) / 40 * 100).clampRange(0, 100);
