/// 自建项目：内置行为库之外的那些（「上一堂课」「陪孩子写作业」……）。
///
/// 三类东西分得很清楚，别混：
///   1. **行为本身**（这张表）：叫什么、算哪个轴、目标量多少 → 用来生成
///      `BehaviorDef`，让采集/结算流程能认出它；
///   2. **刻度**（`user_anchor` / `declared_impact`）：你定的单位与量级；
///   3. **记录**（`daily_log`）：照旧走 `CaptureRepository.commit`。
///
/// 量化路径和内置行为完全一致：`doseFraction = 实际量 / 目标量` →
/// `baseScoreFor()` → EXP = 分 × 权重 × 状态 × 置信 × EXP/点。
/// **这一层不自己算 EXP**，否则两个算法并存必然漂移。
library;

import '../anchor/anchor_models.dart';
import '../enums.dart';
import 'behavior_def.dart';
import 'capture_question.dart';
import 'project_axis.dart';

class CustomBehaviorRecord {
  const CustomBehaviorRecord({
    required this.code,
    required this.name,
    required this.category,
    required this.axis,
    required this.measurementClass,
    required this.unitLabel,
    required this.definitionText,
    required this.targetDose,
    required this.doseUnit,
    required this.tier,
    required this.createdAt,
    this.description = '',
    this.enabled = true,
  });

  /// 稳定机器码（`custom_<时间戳>`）。落库后永不改——改了就丢历史。
  final String code;

  final String name;
  final String description;
  final BehaviorCategory category;
  final ProjectAxis axis;
  final MeasurementClass measurementClass;

  /// 用户定的「一次」叫什么。
  final String unitLabel;

  /// 什么算一次（能事后判断真假）。
  final String definitionText;

  /// 一次的目标量。doseFraction 的分母。
  final double targetDose;

  /// 目标量的单位（分钟 / 次 / 页）。
  final String doseUnit;

  /// 先验档位（只用于展示与折价，不参与分数）。
  final ImpactTier tier;

  final DateTime createdAt;
  final bool enabled;

  CustomBehaviorRecord copyWith({
    String? name,
    String? description,
    BehaviorCategory? category,
    ProjectAxis? axis,
    MeasurementClass? measurementClass,
    String? unitLabel,
    String? definitionText,
    double? targetDose,
    String? doseUnit,
    ImpactTier? tier,
    bool? enabled,
  }) =>
      CustomBehaviorRecord(
        code: code,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        axis: axis ?? this.axis,
        measurementClass: measurementClass ?? this.measurementClass,
        unitLabel: unitLabel ?? this.unitLabel,
        definitionText: definitionText ?? this.definitionText,
        targetDose: targetDose ?? this.targetDose,
        doseUnit: doseUnit ?? this.doseUnit,
        tier: tier ?? this.tier,
        createdAt: createdAt,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'name': name,
        'description': description,
        'category': category.name,
        'axis': axis.name,
        'measurement_class': measurementClass.name,
        'unit_label': unitLabel,
        'definition_text': definitionText,
        'target_dose': targetDose,
        'dose_unit': doseUnit,
        'tier': tier.name,
        'enabled': enabled,
        'created_at': createdAt.toIso8601String(),
      };

  static CustomBehaviorRecord fromJson(Map<String, Object?> json) =>
      CustomBehaviorRecord(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: _category(json['category']?.toString() ?? ''),
        axis: ProjectAxis.parse(json['axis']?.toString() ?? 'strength'),
        measurementClass:
            MeasurementClass.parse(json['measurement_class']?.toString() ?? ''),
        unitLabel: json['unit_label']?.toString() ?? '',
        definitionText: json['definition_text']?.toString() ?? '',
        targetDose: (json['target_dose'] as num?)?.toDouble() ?? 1,
        doseUnit: json['dose_unit']?.toString() ?? '次',
        tier: ImpactTier.parse(json['tier']?.toString() ?? ''),
        enabled: json['enabled'] != false,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime(1970),
      );

  static BehaviorCategory _category(String raw) {
    for (final BehaviorCategory c in BehaviorCategory.values) {
      if (c.name == raw) return c;
    }
    return BehaviorCategory.positive;
  }
}

/// 生成稳定代码。中文名没法做 slug，用时间戳——写库后不再变。
String customBehaviorCode([DateTime? at]) =>
    'custom_${(at ?? DateTime.now()).millisecondsSinceEpoch}';

/// 把一条自建项目变成采集/结算流程认识的行为。
///
/// 只给一道题（这次做了多少），因为自建项目的语义就这么多：
/// 「按我定的单位，今天做了多少」。多想一步就是替用户定义他的生活。
BehaviorDef customBehaviorDef(CustomBehaviorRecord r) {
  final bool negative = r.category == BehaviorCategory.negative;
  final double target = r.targetDose <= 0 ? 1 : r.targetDose;
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
        why: '用你定的单位。不满也照实记——按比例算，不按"没做完"算。',
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
      double fraction = dose / target;
      if (fraction < 0) fraction = 0;
      if (fraction > 1.5) fraction = 1.5;
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
        },
        confidence: ctx.confidenceCeiling,
        doseFraction: fraction,
      );
    },
  );
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
