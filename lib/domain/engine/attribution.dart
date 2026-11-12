/// 归因去重。
///
/// 问题：熬夜 → 第二天没练 → 又扣一次"缺训"，等于一件事罚两遍。
/// 解法：给每条负向事件算一个"根因键"，同键只扣主因，其余记为后果（exp = 0）。
///
/// 根因键格式：`<behaviorCode>@<yyyy-MM-dd>`。
/// 例如 `sleep@2025-06-01`。
library;

import 'package:exp_ledger/core/util/date_key.dart';

class AttributionResult {
  const AttributionResult({
    required this.rootCauseKey,
    this.suppressedBy,
    this.consequenceOf,
  });

  /// 这条事件的根因键。被抑制时等于主因的键。
  final String rootCauseKey;

  /// 非空表示"这条不扣分，因为根因已经扣过了"。
  final String? suppressedBy;

  /// 人类的说法，用于明细页："作为「熬夜」的后果记录，不重复扣分"。
  final String? consequenceOf;

  bool get isSuppressed => suppressedBy != null;
}

/// 根因键。
String rootCauseKeyOf(String behaviorCode, DayKey day) =>
    '$behaviorCode@${day.iso}';

/// 解析一条负向记录的归因。
///
/// [existingRootKeys] 是"今天与昨天已经存在的根因键集合"，
/// 由仓储层在结算前查出来传进来。
AttributionResult resolveAttribution({
  required String behaviorCode,
  required DayKey day,
  required Map<String, Object?> answers,
  required Set<String> existingRootKeys,
}) {
  final own = rootCauseKeyOf(behaviorCode, day);

  // 规则 1：因为太累而缺训 → 根因是睡眠。
  if (behaviorCode == 'training_absence') {
    final reason = answers['reason'];
    if (reason == 'tired') {
      final sleepYesterday = rootCauseKeyOf('sleep', day.addDays(-1));
      final sleepToday = rootCauseKeyOf('sleep', day);
      if (existingRootKeys.contains(sleepYesterday)) {
        return AttributionResult(
          rootCauseKey: sleepYesterday,
          suppressedBy: sleepYesterday,
          consequenceOf: '熬夜',
        );
      }
      if (existingRootKeys.contains(sleepToday)) {
        return AttributionResult(
          rootCauseKey: sleepToday,
          suppressedBy: sleepToday,
          consequenceOf: '熬夜',
        );
      }
    }
  }

  // 规则 2：漏复习如果是"熬夜晚睡"直接导致的，同样归到睡眠。
  if (behaviorCode == 'missed_review') {
    final cause = answers['cause'];
    if (cause == 'late_sleep') {
      final sleepYesterday = rootCauseKeyOf('sleep', day.addDays(-1));
      if (existingRootKeys.contains(sleepYesterday)) {
        return AttributionResult(
          rootCauseKey: sleepYesterday,
          suppressedBy: sleepYesterday,
          consequenceOf: '熬夜',
        );
      }
    }
  }

  // 规则 3：无根因冲突，自己就是根因。
  return AttributionResult(rootCauseKey: own);
}

/// 在一组候选里挑主因：罚得最重的那条当主因，其余同键的一律抑制。
///
/// 之所以按罚分而不是按时间先后挑：主因应该是"最该被看见"的那条，
/// 而不是"最早发生"的那条。
int primaryIndexOf(List<double> penalties) {
  var best = 0;
  for (var i = 1; i < penalties.length; i++) {
    if (penalties[i] > penalties[best]) best = i;
  }
  return penalties.isEmpty ? -1 : best;
}

/// 明细页的说明文案。
String consequenceNote(AttributionResult r) {
  if (!r.isSuppressed) return '';
  return '作为「${r.consequenceOf ?? '同一根因'}」的后果记录，不重复扣分。';
}
