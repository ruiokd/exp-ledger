/// 系统参照区间：让用户在区间上「调整」，而不是从零「发明」。
///
/// 每一档都带 [ReferenceBand.low] / [ReferenceBand.high]（单位与
/// [ReferenceRange.unitSuggestions] 一致），用户点选档位时引擎会用
/// `AnchorEngine.tierFromRange` 把实测值换算回档位。
///
/// 出处纪律（与项目整体一致）：
///   - 只写公共指引的**方向性结论**，不写精确系数，不冒充论文原文；
///   - 每个区间都标 `简化参考`，且带一句 [ReferenceRange.caveat]；
///   - 覆盖不到的行为一律 `custom`，走「自定义单位 + 用户自己标定」，
///     系统只提供倍数档位，不假装知道绝对值。
library;

import 'anchor_models.dart';

/// 一档参照区间。
class ReferenceBand {
  const ReferenceBand({
    required this.tier,
    required this.low,
    required this.high,
    required this.note,
  });

  final ImpactTier tier;

  /// 该档下界（含）。单位见 [ReferenceRange.unitSuggestions]。
  final double low;

  /// 该档上界（不含）。[ImpactTier.large] 用 `double.infinity`。
  final double high;

  final String note;

  bool contains(double value) => value >= low && value < high;
}

class ReferenceRange {
  const ReferenceRange({
    required this.id,
    required this.title,
    required this.measurementClass,
    required this.unitSuggestions,
    required this.bands,
    required this.sourceLabel,
    required this.caveat,
    this.simplified = true,
  });

  final String id;
  final String title;
  final MeasurementClass measurementClass;

  /// 建议的单位措辞。用户可在此基础上改，但不许空着。
  final List<String> unitSuggestions;

  final List<ReferenceBand> bands;

  /// 出处标签。写「简化参考」时必须同时写清依据的方向。
  final String sourceLabel;

  /// 一句话限定。每条都要有。
  final String caveat;

  /// 是否简化参考。目前全是真的——不假装这是精确量表。
  final bool simplified;

  ReferenceBand? bandFor(double value) {
    for (final ReferenceBand b in bands) {
      if (b.contains(value)) return b;
    }
    // 超上界落到最后一档；负值落到第一档。
    if (value < 0) return bands.isEmpty ? null : bands.first;
    return bands.isEmpty ? null : bands.last;
  }

  String get bandSummary => bands
      .map((ReferenceBand b) => '${b.tier.label} ${_fmt(b.low)}–'
          '${b.high.isFinite ? _fmt(b.high) : '以上'}')
      .join(' / ');

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// 内置参照库。**只放能给出方向性依据的类别**，其余走 custom。
const List<ReferenceRange> kReferenceRanges = <ReferenceRange>[
  ReferenceRange(
    id: 'strength_sets',
    title: '力量训练：一次训练的「有效组」数',
    measurementClass: MeasurementClass.formula,
    unitSuggestions: <String>['一次有效组', '组（接近力竭）'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 6,
        note: '维持量，几乎不推动适应',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 6,
        high: 12,
        note: '常见的最低有效量区间',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 12,
        high: 20,
        note: '接近单次训练的量上限，恢复要算进去',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 20,
        high: double.infinity,
        note: '单次超大训练量，需要实测确认你确实扛得住',
      ),
    ],
    sourceLabel: '阻力训练「有效组 / 每周组数」的公共指引方向（简化参考）',
    caveat: '「有效组」指接近力竭且动作质量达标的组，热身组不算。'
        '单次训练量没有公认上限，这里的区间只是量级参照，不是处方。',
  ),
  ReferenceRange(
    id: 'sleep_hours',
    title: '睡眠：一夜实际睡着的小时数',
    measurementClass: MeasurementClass.formula,
    unitSuggestions: <String>['小时'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 8.5,
        high: double.infinity,
        note: '充足，通常不需要额外补',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 7,
        high: 8.5,
        note: '多数成人的推荐区间',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 5.5,
        high: 7,
        note: '短睡，次日状态通常可见下降',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 0,
        high: 5.5,
        note: '显著不足，按缺口累积处理',
      ),
    ],
    sourceLabel: '成人睡眠时长建议的公共指引区间（简化参考）',
    caveat: '个体需求差异很大，长期短睡的人主观感受会钝化。'
        '这里的档位只用于量级换算，不构成睡眠诊断；持续失眠请就医。',
  ),
  ReferenceRange(
    id: 'writing_output',
    title: '写作：一次坐下来完成的产出',
    measurementClass: MeasurementClass.formula,
    unitSuggestions: <String>['完成段落', '字', '一页'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 300,
        note: '记录想法、改标题这种量级',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 300,
        high: 800,
        note: '一次有效写作',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 800,
        high: 2000,
        note: '一次长写作，通常要预留整块时间',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 2000,
        high: double.infinity,
        note: '单次超长产出，靠实测确认可持续',
      ),
    ],
    sourceLabel: '写作习惯类公共经验的量级划分（简化参考，无统一标准）',
    caveat: '字数不等于价值，这里只量「投入的量」。'
        '如果换了单位（段落 / 页），请重标定一次，旧记录不追溯。',
  ),
  ReferenceRange(
    id: 'deep_conversation',
    title: '深度对话 / 情绪劳动：一次持续多久',
    measurementClass: MeasurementClass.subjective,
    unitSuggestions: <String>['一次 20 分钟以上的深谈', '分钟'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 15,
        note: '寒暄量级，几乎没有情绪负荷',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 15,
        high: 40,
        note: '一次真正的谈话',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 40,
        high: 90,
        note: '长谈，通常当天做不了别的重活',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 90,
        high: double.infinity,
        note: '超长情绪负荷，往往要几天才回稳',
      ),
    ],
    sourceLabel: '情绪劳动负荷的量级划分（简化参考，属于主观可辨类）',
    caveat: '这类行为没有可查证的公式：只记单位和档位、看趋势，'
        '不折成 EXP，也不参与扣分。档位代表你的主观可辨差异，不代表客观剂量。',
  ),
  ReferenceRange(
    id: 'passive_scroll',
    title: '被动刷手机：一天累计时长',
    measurementClass: MeasurementClass.semiObservable,
    unitSuggestions: <String>['分钟'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 60,
        note: '零散使用',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 60,
        high: 150,
        note: '明显占了闲余时间',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 150,
        high: 300,
        note: '挤掉了原计划的事',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 300,
        high: double.infinity,
        note: '整天被切碎，通常伴随回避',
      ),
    ],
    sourceLabel: '屏幕使用时长的公共指引方向（简化参考）',
    caveat: '半可观测行为只呈现时间占比，不给精确分。'
        '使用时长与危害不是线性关系，别把它当惩罚依据。',
  ),
  ReferenceRange(
    id: 'chores_care',
    title: '家务 / 育儿：一次完整做完的量',
    measurementClass: MeasurementClass.subjective,
    unitSuggestions: <String>['一次完整家务', '小时'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 20,
        note: '顺手就做了',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 20,
        high: 60,
        note: '占掉一段可支配时间',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 60,
        high: 180,
        note: '占掉大半天，别的事基本做不了',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 180,
        high: double.infinity,
        note: '整天都在做这个',
      ),
    ],
    sourceLabel: '无酬照护与家务时间投入的量级划分（简化参考）',
    caveat: '这类事经常不被计入「今天的成果」，所以更要单独记。'
        '只记单位与档位，看趋势；不折成 EXP，也不参与扣分。',
  ),
  ReferenceRange(
    id: 'custom',
    title: '自定义：系统不假装知道你这件事的绝对量',
    measurementClass: MeasurementClass.subjective,
    unitSuggestions: <String>['自定义单位'],
    bands: <ReferenceBand>[
      ReferenceBand(
        tier: ImpactTier.small,
        low: 0,
        high: 0.5,
        note: '不到你心里那个「一次」的一半',
      ),
      ReferenceBand(
        tier: ImpactTier.medium,
        low: 0.5,
        high: 1.2,
        note: '大约就是你心里的「一次」',
      ),
      ReferenceBand(
        tier: ImpactTier.mediumHigh,
        low: 1.2,
        high: 2.5,
        note: '明显超过一次，两倍上下',
      ),
      ReferenceBand(
        tier: ImpactTier.large,
        low: 2.5,
        high: double.infinity,
        note: '很多次，或者一次就把整天占了',
      ),
    ],
    sourceLabel: '按「以你自定义的一次为 1.0」的倍数分档',
    caveat: '没有外部参照，只有你自己的倍数刻度。'
        '这些档位不参与结算，只用来在图表上给你一个形状。',
  ),
];

ReferenceRange? referenceRangeById(String id) {
  for (final ReferenceRange r in kReferenceRanges) {
    if (r.id == id) return r;
  }
  return null;
}

/// 按可量化程度挑候选项。引导流程 Step 2 只展示这一组。
List<ReferenceRange> referenceRangesFor(MeasurementClass cls) {
  final List<ReferenceRange> out = kReferenceRanges
      .where((ReferenceRange r) => r.measurementClass == cls)
      .toList(growable: false);
  if (out.isEmpty) {
    return <ReferenceRange>[referenceRangeById('custom')!];
  }
  return out;
}
