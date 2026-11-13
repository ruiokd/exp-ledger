/// 自建项目 → 采集/结算流程认识的 [BehaviorDef]。
///
/// 从 `custom_behavior.dart` 切出来的：那一半是**数据**（落库的字段），
/// 这一半是**适配器**（把数据翻译成行为库能吃的定义）。
/// 混在一起时，模型文件会为了一个 `derive` 闭包把 quant 层拖进来。
library;

import '../enums.dart';
import '../quant/quant.dart';
import 'behavior_def.dart';
import 'capture_question.dart';
import 'custom_behavior.dart';

/// 自建项目的默认口径：linear + 单个维度。
///
/// 这是**唯一**的基线定义处：仓储在建项目时写它，`customBehaviorDef`
/// 在没有库里口径时也用它。两处各写一遍迟早漂移（这正是 v1.0.x 的教训）。
QuantSpec linearBaselineFor(
  CustomBehaviorRecord r, {
  String source = 'userPrior',
  String note = '',
}) =>
    QuantSpec(
      behaviorCode: r.code,
      measureKind: MeasureKind.guessFromUnit(r.doseUnit),
      measureUnit: r.doseUnit,
      shape: const DoseShapeSpec.linear(),
      targetDose: r.targetDose <= 0 ? 1 : r.targetDose,
      impact: <ImpactShare>[
        ImpactShare(
          axisKey: r.axis.name,
          axisLabel: r.axis.label,
          kind: AxisKind.ability,
          share: 1,
        ),
      ],
      citation: '自建项目默认口径：按目标量线性折算',
      source: source,
      note: note,
    );

/// 把一条自建项目变成采集/结算流程认识的行为。
///
/// 只给一道题（这次做了多少），因为自建项目的语义就这么多：
/// 「按我定的单位，今天做了多少」。多想一步就是替用户定义他的生活。
///
/// [quant] 是库里这条行为的量化口径（`behavior_quant_spec`）。
/// 传 null 时退回 [linearBaselineFor]——与 v1.1.x 的行为完全一致，
/// 所以"老项目没口径行"这种事不会改变任何一条历史记录。
BehaviorDef customBehaviorDef(CustomBehaviorRecord r, {QuantSpec? quant}) {
  final bool negative = r.category == BehaviorCategory.negative;
  final QuantSpec spec = quant ?? linearBaselineFor(r);
  final double target = spec.targetDose <= 0 ? 1 : spec.targetDose;
  final double maxDose = target * 3;

  return BehaviorDef(
    code: r.code,
    name: r.name,
    category: r.category,
    valence: negative ? Valence.negative : Valence.positive,
    axis: r.axis,
    iconName: 'dot',
    aliases: <String>[
      r.name,
      if (r.description.trim().isNotEmpty) r.description.trim(),
    ],
    keywords: <String>[r.unitLabel, r.doseUnit],
    standardDefinition: r.definitionText.trim().isEmpty
        ? '一次 = ${r.unitLabel}'
        : r.definitionText.trim(),
    misconception: '这是你自己建的项目：量化按你定的单位与目标量走，不套内置公式。',
    targetDose: target,
    doseUnit: r.doseUnit,
    slotScope: SlotScope.perDay,
    questions: <QuestionSpec>[
      QuestionSpec(
        id: 'dose',
        title: '这次${r.doseUnit}多少？',
        why: '用你定的单位。不满也照实记——按你定的折算方式算，不按"没做完"算。',
        kind: QuestionKind.number,
        inheritFromLast: true,
        rangeHint: '一次通常 ${_fmt(target)}${r.doseUnit}',
        numberSpec: NumberSpec(
          min: 0,
          max: maxDose,
          initial: target,
          step: 1,
          unit: r.doseUnit,
        ),
      ),
    ],
    derive: (DeriveContext ctx) {
      final double dose = ctx.numOr('dose', target);
      // 唯一的算术出口：口径怎么折算由 QuantSpec 决定，这里不自己除。
      final double fraction = spec.doseFractionFor(dose);
      final bool full = fraction >= 0.999;
      return DerivedResult(
        slotKey: 'main',
        interpretation: full
            ? '${r.name}：${_fmt(dose)}${r.doseUnit}（目标 ${_fmt(target)}${r.doseUnit}）'
            : '${r.name}：${_fmt(dose)}${r.doseUnit}，是目标 ${_fmt(target)}${r.doseUnit} 的 '
                '${(fraction * 100).round()}%',
        lines: <ReceiptLine>[
          ReceiptLine('做了一次', '${_fmt(dose)}${r.doseUnit}'),
          ReceiptLine('目标量', '${_fmt(target)}${r.doseUnit}'),
          ReceiptLine('折算方式', spec.shape.describe(dose, target)),
          ReceiptLine(
            '计入比例',
            '${(fraction * 100).round()}%',
            emphasis: true,
          ),
          ReceiptLine('刻度档位', '${r.tier.label}（先验，未实测）'),
        ],
        metrics: <String, double>{
          'dose': dose,
          'target_dose': target,
          'fraction': fraction,
        },
        normalized: <String, Object?>{
          'dose': dose,
          'target_dose': target,
          'tier': r.tier.name,
          'custom': true,
          'shape': spec.shape.kind.name,
          'measure': spec.measureKind.name,
        },
        confidence: ctx.confidenceCeiling,
        doseFraction: fraction,
      );
    },
  );
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
