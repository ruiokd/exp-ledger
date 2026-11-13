/// 自建项目：内置行为库之外的那些（「上一堂课」「陪孩子写作业」……）。
///
/// 三类东西分得很清楚，别混：
///   1. **行为本身**（这张表）：叫什么、算哪个轴、目标量多少 → 用来生成
///      `BehaviorDef`，让采集/结算流程能认出它；
///   2. **刻度**（`user_anchor` / `declared_impact`）：你定的单位与量级；
///   3. **记录**（`daily_log`）：照旧走 `CaptureRepository.commit`。
///
/// 量化路径和内置行为完全一致：`doseFraction = 口径折算(实际量)` →
/// `baseScoreFor()` → EXP = 分 × 权重 × 状态 × 置信 × EXP/点。
/// **这一层不自己算 EXP**，否则两个算法并存必然漂移。
///
/// 「口径折算」从 v1.2.0 起由 `domain/quant` 的 [QuantSpec] 决定：
/// 线性时就是 `实际量 / 目标量`（与 v1.1.x 逐字等价），
/// 换成对数/饱和/事件型之后，变化只发生在"没做满算几成"这一段。
library;

import '../anchor/anchor_models.dart';
import '../enums.dart';
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
