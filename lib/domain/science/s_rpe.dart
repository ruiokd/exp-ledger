/// 训练内负荷：session-RPE。
///
/// 出处：Foster et al., 2001（session-RPE 法）。
/// 公式：sRPE = RPE(0–10) × 时长(分钟)。
///
/// 必须随展示一起标注的两句话：
///   1. 这是**简化版**，只依赖主观感受；
///   2. 个体之间不可直接比较（同样的 RPE，不同人的实际生理负荷不同）。
library;

import 'package:exp_ledger/core/util/num_ext.dart';

/// 一次课的 session-RPE 负荷。
double srpeLoad({required double rpe, required double minutes}) {
  if (minutes <= 0) return 0;
  final r = rpe.clampRange(0, 10);
  return r * minutes;
}

/// 从抗阻训练的 RIR 反推 RPE：RIR ≈ 10 − RPE。
double rpeFromRir(int rir) => (10 - rir).clampRange(0, 10);

/// 从有氧强度档位估 RPE。档位是粗分，误差较大。
double rpeFromIntensityBand(String band) => switch (band) {
      'low' => 3.0,
      'mid' => 6.0,
      'high' => 8.5,
      _ => 6.0,
    };

/// 判断是否属于"高强度日"。sRPE ≥ 该阈值视为高负荷。
const double kHighLoadSrpeThreshold = 400;

bool isHighLoadDay(double srpe) => srpe >= kHighLoadSrpeThreshold;

/// session-RPE 的自洽性检查：时长与 RPE 明显矛盾时给一条中性提示。
/// 返回 null 表示没意见。
String? srpeConsistencyNote({required double rpe, required double minutes}) {
  if (rpe >= 9 && minutes >= 120) {
    return '这个时长配这个强度已经很重，之后 48 小时注意同一部位的恢复。';
  }
  if (rpe <= 2 && minutes <= 5) {
    return '这次负荷很轻，会计入记录但不足以构成刺激。';
  }
  return null;
}
