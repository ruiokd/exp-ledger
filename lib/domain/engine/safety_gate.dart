/// 安全兜底。
///
/// 位置在整条流水线的**第 0 位**：先判安全，再谈算分。
/// 触发时当日结算暂停——不产出正分，也不产出负分，
/// 因为在这种输入下继续算分只会误导用户。
///
/// 三条铁律：
///   1. 只做"提示 + 建议就医"，绝不下诊断；
///   2. 文案不指责（不说"你这样很危险"，说"这组输入超出了常规范围"）；
///   3. 暂停结算不等于清零，之前的记录全都在。
library;

import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';

/// 触发兜底的关键词。只做提示，不做医学判断。
const List<String> kRedFlagKeywords = [
  '横纹肌溶解',
  '酱油色尿',
  '可乐色尿',
  '胸痛',
  '胸闷',
  '晕厥',
  '眼前发黑',
  '心悸',
  '呼吸困难',
  '剧烈头痛',
  '呕吐不止',
];

class SafetyGate {
  const SafetyGate();

  /// 返回 null 表示安全。
  SafetyAlert? check({
    required List<DraftEntry> drafts,
    required StateVars state,
    int consecutiveHighIntensityDays = 0,
  }) {
    // ---- 规则 1：关键词命中 → 立即暂停，建议就医 ----
    for (final d in drafts) {
      final text = <String>[
        d.interpretation,
        ...d.answers.values.whereType<String>(),
        ...d.notes,
      ].join(' ');
      for (final kw in kRedFlagKeywords) {
        if (text.contains(kw)) {
          return SafetyAlert(
            code: 'red_flag_keyword',
            title: '先停一下',
            message: '你提到了「$kw」这类信号，这组输入已经超出日常记录的范围，'
                '今天先不算分。',
            advice: '如果症状持续、加重或反复出现，请及时就医。'
                '本 App 只做记录与提示，不做诊断。',
          );
        }
      }
    }

    // ---- 规则 2：极大量训练 + 极少睡眠 ----
    final trainingMinutes = drafts
        .where((d) =>
            d.behaviorCode == 'strength_training' || d.behaviorCode == 'cardio')
        .fold<double>(
            0,
            (sum, d) =>
                sum +
                (d.metrics['session_minutes'] ?? d.metrics['minutes'] ?? 0));

    double? recordedSleepHours;
    for (final d in drafts) {
      if (d.behaviorCode == 'sleep') {
        recordedSleepHours = d.metrics['effective_hours'];
      }
    }
    // 没记录睡眠时，用状态变量推断：有负债就按不足处理。
    final sleepHours =
        recordedSleepHours ?? (state.sleepDebtHours > 0.5 ? 0.0 : 7.5);

    if (trainingMinutes >= 180 && sleepHours < 5) {
      return SafetyAlert(
        code: 'extreme_load_low_sleep',
        title: '今天先不算分',
        message: '训练 ${trainingMinutes.round()} 分钟，睡眠 ${sleepHours.toStringAsFixed(1)} 小时，'
            '这组组合超出了常规恢复能力。',
        advice: '先补水和进食，今天不要再加练。若出现肌肉剧痛、'
            '肿胀、尿色变深，请尽快就医。本 App 不做诊断。',
      );
    }

    // ---- 规则 3：连续多日极高强度 → 只提示，不阻断 ----
    if (consecutiveHighIntensityDays >= 3) {
      return SafetyAlert(
        code: 'consecutive_high_load',
        title: '连续高强度',
        message: '已经连续 $consecutiveHighIntensityDays 天高强度训练，恢复窗口被压得很薄。',
        advice: '建议明天安排一次低强度或完全休息。'
            '若出现持续关节疼痛或异常乏力，请就医评估。',
        blocking: false,
      );
    }

    return null;
  }
}
