/// 一条行为的量化规格：怎么量、怎么折算、落到哪些维度。
///
/// 这一层**不产生 EXP**，也不做校验（校验在 `quant_validate.dart`）。
/// 它只把"原始量"压成 `doseFraction`，之后照旧走 `baseScoreFor → score → EXP`。
library;

import 'axis_registry.dart';
import 'dose_shape.dart';
import 'quant_measure.dart';

/// 一条行为的量化规格。
class QuantSpec {
  const QuantSpec({
    required this.behaviorCode,
    required this.measureKind,
    required this.measureUnit,
    required this.shape,
    required this.targetDose,
    required this.impact,
    this.howToCheck = '',
    this.citation = '',
    this.source = 'userPrior',
    this.note = '',
  });

  final String behaviorCode;
  final MeasureKind measureKind;
  final String measureUnit;
  final DoseShapeSpec shape;
  final double targetDose;
  final List<ImpactShare> impact;
  final String howToCheck;
  final String citation;

  /// `userPrior` 或 `aiProposal`。确认动作把它变成前者（与刻度层一致）。
  final String source;

  final String note;

  /// 超额封顶。与 `custom_behavior.dart` 里现行的 1.5 一致；
  /// v1.2.0 接线时整体搬进 `BalanceConfig`，这里先显式写成常量便于审查。
  static const double doseFractionCeiling = 1.5;

  /// 原始量 → `doseFraction`。**这是全层唯一的算术出口。**
  double doseFractionFor(double dose) {
    final double raw = shape.fractionFor(dose, targetDose);
    if (raw.isNaN) return 0;
    if (raw <= 0) return 0;
    if (raw > doseFractionCeiling) return doseFractionCeiling;
    return raw;
  }

  /// 主维度：份额最大的那个。首版只支持「一个主维度 + 若干体验维度」。
  ImpactShare? get primary {
    if (impact.isEmpty) return null;
    ImpactShare best = impact.first;
    for (final ImpactShare s in impact) {
      if (s.share > best.share) best = s;
    }
    return best;
  }

  List<ImpactShare> get experienceShares =>
      impact.where((ImpactShare s) => s.kind == AxisKind.experience).toList();

  /// 能力维度份额合计。`>0` 表示这条行为会推主曲线。
  double get abilityShare => impact
      .where((ImpactShare s) => s.kind == AxisKind.ability)
      .fold(0.0, (double a, ImpactShare s) => a + s.share);

  /// 这条行为是否真的会进入结算（体验维度 EXP 权重恒 0）。
  bool get contributesExp => abilityShare > 0 && measureKind != MeasureKind.rating;

  /// 把口径挂到另一个行为码上（建项目时先攒出一个草稿口径，
  /// 正式 code 要等落库才算得出来）。目标量与单位以调用方为准：
  /// 用户在预览页改过的那两个数必须赢过 AI 给的值。
  QuantSpec forBehavior(
    String code, {
    double? targetDose,
    String? measureUnit,
  }) =>
      QuantSpec(
        behaviorCode: code,
        measureKind: measureKind,
        measureUnit: measureUnit ?? this.measureUnit,
        shape: shape,
        targetDose: targetDose ?? this.targetDose,
        impact: impact,
        howToCheck: howToCheck,
        citation: citation,
        source: source,
        note: note,
      );

  QuantSpec copyWith({
    MeasureKind? measureKind,
    String? measureUnit,
    DoseShapeSpec? shape,
    double? targetDose,
    List<ImpactShare>? impact,
    String? howToCheck,
    String? citation,
    String? source,
    String? note,
  }) =>
      QuantSpec(
        behaviorCode: behaviorCode,
        measureKind: measureKind ?? this.measureKind,
        measureUnit: measureUnit ?? this.measureUnit,
        shape: shape ?? this.shape,
        targetDose: targetDose ?? this.targetDose,
        impact: impact ?? this.impact,
        howToCheck: howToCheck ?? this.howToCheck,
        citation: citation ?? this.citation,
        source: source ?? this.source,
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_code': behaviorCode,
        'measure_kind': measureKind.name,
        'measure_unit': measureUnit,
        'shape': shape.toJson(),
        'target_dose': targetDose,
        'impact': impact.map((ImpactShare s) => s.toJson()).toList(),
        'how_to_check': howToCheck,
        'citation': citation,
        'source': source,
        'note': note,
      };

  static QuantSpec? fromJson(Map<String, Object?> json) {
    final String code = json['behavior_code']?.toString() ?? '';
    final MeasureKind? kind =
        MeasureKind.tryParse(json['measure_kind']?.toString());
    if (code.isEmpty || kind == null) return null;
    final List<ImpactShare> impact = <ImpactShare>[];
    final Object? rawImpact = json['impact'];
    if (rawImpact is List) {
      for (final Object? item in rawImpact) {
        if (item is Map) {
          final ImpactShare? s =
              ImpactShare.fromJson(Map<String, Object?>.from(item));
          if (s != null) impact.add(s);
        }
      }
    }
    return QuantSpec(
      behaviorCode: code,
      measureKind: kind,
      measureUnit: json['measure_unit']?.toString() ?? kind.defaultUnit,
      shape: DoseShapeSpec.parseOrDefault(
        json['shape'] is Map
            ? Map<String, Object?>.from(json['shape'] as Map)
            : null,
      ),
      targetDose: (json['target_dose'] as num?)?.toDouble() ?? 0,
      impact: impact,
      howToCheck: json['how_to_check']?.toString() ?? '',
      citation: json['citation']?.toString() ?? '',
      source: json['source']?.toString() ?? 'userPrior',
      note: json['note']?.toString() ?? '',
    );
  }
}

