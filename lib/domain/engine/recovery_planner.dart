/// 可回补路径生成。
///
/// 规则：扣分必须配一条可执行的出路，且出路必须具体
/// （"连续 3 晚 23:30 前入睡"），不能是"注意休息"这种废话。
library;

import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';

/// 按影响大小排序，返回最多 3 条。
List<String> buildRecoveryPlan({
  required List<NegativeEvent> negatives,
  required StateVars state,
}) {
  final entries = <_Hint>[];

  for (final n in negatives) {
    for (final h in n.recoveryHints) {
      entries.add(_Hint(h, n.exp.abs()));
    }
  }

  if (state.sleepDebtHours > 0.5) {
    final nights = (state.sleepDebtHours / 1.5).ceil().clamp(1, 5);
    entries.add(_Hint(
      '连续 $nights 晚比平时早 45 分钟上床，睡眠负债大约能回补六成',
      state.sleepDebtHours * 2,
    ));
  }

  if (state.damageLoad > 1) {
    entries.add(_Hint(
      '接下来 3 天把训练量降到平时的 60%，避免同一肌群连续大负荷',
      state.damageLoad * 1.5,
    ));
  }

  if (state.recoveryDebt > 1) {
    entries.add(_Hint(
      '安排一天完全休息，或者只做 15 分钟低强度活动',
      state.recoveryDebt,
    ));
  }

  entries.sort((a, b) => b.weight.compareTo(a.weight));

  final unique = <String>[];
  for (final e in entries) {
    if (!unique.contains(e.text)) unique.add(e.text);
    if (unique.length >= 3) break;
  }
  return unique;
}

class _Hint {
  const _Hint(this.text, this.weight);

  final String text;
  final double weight;
}

/// 负向事件的默认回补话术（行为自身没给时兜底）。
String defaultRecoveryHint(String behaviorCode) => switch (behaviorCode) {
      'sleep' => '今晚把入睡时间提前 45 分钟，明天就能看到负债条短一截',
      'sedentary' => '下一个整点起来走 2 分钟，久坐的这一段就能被抵消一部分',
      'alcohol_over' => '今晚多喝一杯水，明早的静息心率会告诉你恢复得怎么样',
      'sugary_drink' => '下次换成无糖的，这一项就不会再出现在明细里',
      'binge_eating' => '下一餐正常吃，不用补偿性节食',
      'missed_review' => '把漏掉的词拆成两天各一半，比一次补完更有效',
      'training_absence' => '下一次训练从计划的 70% 开始，不用一次追平',
      'doomscrolling' => '把手机放到另一个房间，20 分钟就够打断这个循环',
      'smoking' => '这条记录的用途是让你看见趋势，不是给你打分',
      _ => '把明天的记录补全，趋势会自己走回来',
    };
