/// 导出端：生成给网页 AI 的请求文本。
///
/// 从 `quant_codec.dart` 切出来的两半之一。这一半只管"话怎么说清楚"，
/// 不解析任何东西；把解析放在一起会让人以为导入失败和导出失败是同一类问题。
library;

import 'axis_registry.dart';

/// 请求里的一个目标：用户已经建好、但还没说清"怎么量"的项目。
class QuantRequestTarget {
  const QuantRequestTarget({
    required this.code,
    required this.name,
    this.definition = '',
    this.targetDose = 0,
    this.doseUnit = '',
    this.note = '',
  });

  final String code;
  final String name;
  final String definition;
  final double targetDose;
  final String doseUnit;
  final String note;
}

/// 生成请求文本。用户手动贴给网页 AI——App 没有 INTERNET 权限，
/// 也不需要：这一步是人肉通道。
String buildQuantRequestText({
  required List<QuantRequestTarget> targets,
  AxisRegistry registry = const AxisRegistry(),
  String appVersion = '',
}) {
  final StringBuffer b = StringBuffer();

  b.writeln('你在帮我给「经验账本」里的行为定数量口径。');
  b.writeln('只做两件事：**选一种折算形状**、**填档位参数**。');
  b.writeln('不要输出公式，不要输出小数系数，不要自己发明维度类型。');
  b.writeln('');

  b.writeln('## 一、形状只能从这四种里选（名字必须逐字一致）');
  b.writeln('');
  b.writeln('| kind | 语义 | 参数 | 什么时候用 |');
  b.writeln('|---|---|---|---|');
  b.writeln('| linear | 做多少算多少 | 无 | 可线性累积：背单词、组数、页数 |');
  b.writeln('| log | 边际递减 | k，只能取 0.5 / 1 / 2 / 4 | 前段有效后段递减：阅读、写作、练习 |');
  b.writeln('| saturating | 有上限 | 无 | 有生理或时间上限：陪伴、冥想、拉伸 |');
  b.writeln('| threshold | 要么发生要么没发生 | theta_fraction，只能取 1 或 0.5 | 事件型：看一场电影、一次约会、体检 |');
  b.writeln('');
  b.writeln('四种形状都已归一化：**做到目标量时一律等于 1.0**。');
  b.writeln('所以参数只改"没做满时算几成"，不影响满分线。');
  b.writeln('');

  b.writeln('## 二、维度只能从这张表里选（或者新建，但要给依据）');
  b.writeln('');
  for (final AxisSpec a in registry.all) {
    b.writeln('- `${a.key}` = ${a.label}（${a.kind.label}）');
  }
  b.writeln('');
  b.writeln('`ability` 维度会进能力曲线；`experience` 维度只记频次与主观分，不算能力值。');
  b.writeln('新建维度时 `axis` 用 snake_case 英文，并给 `axis_label`。');
  b.writeln('如果你把一个**新维度**标成 `ability`，必须同时给 `decay_tau_days`');
  b.writeln('（停止后大概几天掉回基线）和 `decay_citation`（依据）。说不出来就标 `experience`。');
  b.writeln('');

  b.writeln('## 三、份额规则');
  b.writeln('');
  b.writeln('- 所有 `share` 加起来必须是 1；');
  b.writeln('- 首版**只允许一个 ability 维度**（多轴分摊会破坏结算的唯一约束）；');
  b.writeln('- `measure.kind = rating`（主观分）时不能有 ability 维度。');
  b.writeln('');

  b.writeln('## 四、要量的行为');
  b.writeln('');
  for (final QuantRequestTarget t in targets) {
    b.writeln('### ${t.name}');
    b.writeln('- behavior_code: `${t.code}`');
    if (t.definition.trim().isNotEmpty) {
      b.writeln('- 什么算一次：${t.definition.trim()}');
    }
    if (t.targetDose > 0) {
      b.writeln('- 现有目标量：${_fmt(t.targetDose)}${t.doseUnit}');
    } else {
      b.writeln('- 目标量：还没定，请你给一个（同单位）');
    }
    if (t.note.trim().isNotEmpty) {
      b.writeln('- 补充：${t.note.trim()}');
    }
    b.writeln('');
  }

  b.writeln('## 五、输出格式（严格 JSON，不要任何解释文字）');
  b.writeln('');
  b.writeln('```json');
  b.writeln('{');
  b.writeln('  "items": [');
  b.writeln('    {');
  b.writeln('      "behavior_code": "上面的 code 原样抄",');
  b.writeln('      "measure": {');
  b.writeln('        "kind": "duration_min | count | episode | rating",');
  b.writeln('        "unit": "分钟",');
  b.writeln('        "how_to_check": "事后怎么判断这次算不算/算多少"');
  b.writeln('      },');
  b.writeln('      "shape": { "kind": "linear | log | saturating | threshold",');
  b.writeln('                 "k": 1, "theta_fraction": 1 },');
  b.writeln('      "target_dose": 30,');
  b.writeln('      "impact": [');
  b.writeln('        { "axis": "discipline", "axis_label": "自律",');
  b.writeln('          "dim_kind": "ability | experience", "share": 1.0 }');
  b.writeln('      ],');
  b.writeln('      "rationale": "为什么选这个形状（一句话）",');
  b.writeln('      "citation": "依据；没有依据就写 无"');
  b.writeln('    }');
  b.writeln('  ]');
  b.writeln('}');
  b.writeln('```');
  b.writeln('');
  b.writeln('## 六、会被打回的情况');
  b.writeln('');
  b.writeln('- 形状名不在四种里；');
  b.writeln('- `k` 不是 0.5/1/2/4，或 `theta_fraction` 不是 1/0.5；');
  b.writeln('- `target_dose` 缺失或 ≤ 0；');
  b.writeln('- 份额之和不是 1（会被按比例改掉，并在界面上告诉你）；');
  b.writeln('- 两个以上 ability 维度；');
  b.writeln('- `rating` 却挂了 ability 维度；');
  b.writeln('- 新 ability 维度没有 `decay_tau_days` / `decay_citation`（会被降级为 experience）。');
  if (appVersion.trim().isNotEmpty) {
    b.writeln('');
    b.writeln('（账本版本 $appVersion，协议 v1）');
  }
  return b.toString();
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
