/// 量化规格的校验：四道闸 + 份额归一 + 新维度降级。
///
/// 校验顺序是契约的一部分：先判"这条能不能收"，再纠正"份额怎么分"。
library;

import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:test/test.dart';

const AxisRegistry registry = AxisRegistry();

QuantSpec specOf({
  String code = 'custom_1',
  MeasureKind measure = MeasureKind.durationMin,
  String unit = '分钟',
  DoseShapeSpec shape = const DoseShapeSpec.linear(),
  double target = 30,
  List<ImpactShare>? impact,
  String howToCheck = '',
  String citation = '',
}) =>
    QuantSpec(
      behaviorCode: code,
      measureKind: measure,
      measureUnit: unit,
      shape: shape,
      targetDose: target,
      impact: impact ??
          const <ImpactShare>[
            ImpactShare(
              axisKey: 'discipline',
              axisLabel: '自律',
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
      howToCheck: howToCheck,
      citation: citation,
    );

List<String> codesOf(QuantValidation v) =>
    v.issues.map((QuantIssue q) => q.code).toList();

void main() {
  group('量法的两套名字（协议 snake_case / 枚举 camelCase）', () {
    test('tryParse 两种都认', () {
      expect(MeasureKind.tryParse('duration_min'), MeasureKind.durationMin);
      expect(MeasureKind.tryParse('durationMin'), MeasureKind.durationMin);
      expect(MeasureKind.tryParse('count'), MeasureKind.count);
      expect(MeasureKind.tryParse('episode'), MeasureKind.episode);
      expect(MeasureKind.tryParse('rating'), MeasureKind.rating);
    });

    test('不认识的还是 null（不猜）', () {
      expect(MeasureKind.tryParse('vibes'), isNull);
      expect(MeasureKind.tryParse(''), isNull);
    });

    test('wire 名互不重复，且都不是空串', () {
      final Set<String> wires =
          MeasureKind.values.map((MeasureKind k) => k.wire).toSet();
      expect(wires.length, MeasureKind.values.length);
      expect(wires.contains(''), isFalse);
    });
  });

  group('能收的情况', () {
    test('时长 + 线性 + 单个能力维度', () {
      final QuantValidation v = validateQuantSpec(specOf(), registry: registry);
      expect(v.accepted, isTrue, reason: v.issues.toString());
      expect(v.spec.impact.single.axisKey, 'discipline');
      expect(v.spec.contributesExp, isTrue);
    });

    test('事件型 + 阈值 = 看电影这类', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          measure: MeasureKind.episode,
          unit: '次',
          target: 1,
          shape: const DoseShapeSpec(kind: DoseShape.threshold),
        ),
        registry: registry,
      );
      expect(v.accepted, isTrue, reason: v.issues.toString());
      expect(v.spec.doseFractionFor(1), 1);
      expect(v.spec.doseFractionFor(0.5), 0);
    });

    test('体验维度不产生 EXP', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'relation',
              axisLabel: '关系',
              kind: AxisKind.experience,
              share: 1,
            ),
          ],
        ),
        registry: registry,
      );
      expect(v.accepted, isTrue, reason: v.issues.toString());
      expect(v.spec.contributesExp, isFalse);
      expect(v.spec.abilityShare, 0);
    });
  });

  group('打回：形状与量法不匹配', () {
    test('时长型用阈值 → R_SHAPE_MISMATCH', () {
      final QuantValidation v = validateQuantSpec(
        specOf(shape: const DoseShapeSpec(kind: DoseShape.threshold)),
        registry: registry,
      );
      expect(v.accepted, isFalse);
      expect(codesOf(v), contains('R_SHAPE_MISMATCH'));
    });

    test('自由参数 k=0.37 → R_FREE_PARAM', () {
      final QuantValidation v = validateQuantSpec(
        specOf(shape: const DoseShapeSpec(kind: DoseShape.log, logK: 0.37)),
        registry: registry,
      );
      expect(v.accepted, isFalse);
      expect(codesOf(v), contains('R_FREE_PARAM'));
    });

    test('目标量 0 → R_TARGET_REQUIRED', () {
      final QuantValidation v =
          validateQuantSpec(specOf(target: 0), registry: registry);
      expect(codesOf(v), contains('R_TARGET_REQUIRED'));
    });

    test('空行为码 → R_NO_CODE', () {
      final QuantValidation v =
          validateQuantSpec(specOf(code: '  '), registry: registry);
      expect(codesOf(v), contains('R_NO_CODE'));
    });

    test('没有维度 → R_NO_IMPACT', () {
      final QuantValidation v = validateQuantSpec(
        specOf(impact: const <ImpactShare>[]),
        registry: registry,
      );
      expect(codesOf(v), contains('R_NO_IMPACT'));
    });

    test('主观分挂能力维度 → R_RATING_NOT_ABILITY', () {
      final QuantValidation v = validateQuantSpec(
        specOf(measure: MeasureKind.rating, unit: '分', target: 10),
        registry: registry,
      );
      expect(v.accepted, isFalse);
      expect(codesOf(v), contains('R_RATING_NOT_ABILITY'));
    });

    test('两个能力维度 → R_MULTI_ABILITY_UNSUPPORTED（首版不做多轴分摊）', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'strength',
              axisLabel: '体能',
              kind: AxisKind.ability,
              share: 0.5,
            ),
            ImpactShare(
              axisKey: 'discipline',
              axisLabel: '自律',
              kind: AxisKind.ability,
              share: 0.5,
            ),
          ],
        ),
        registry: registry,
      );
      expect(v.accepted, isFalse);
      expect(codesOf(v), contains('R_MULTI_ABILITY_UNSUPPORTED'));
    });
  });

  group('纠正后收下', () {
    test('份额合计 1.2 → 按比例归一，并留一条说明', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'discipline',
              axisLabel: '自律',
              kind: AxisKind.ability,
              share: 0.6,
            ),
            ImpactShare(
              axisKey: 'relation',
              axisLabel: '关系',
              kind: AxisKind.experience,
              share: 0.6,
            ),
          ],
        ),
        registry: registry,
      );
      expect(v.accepted, isTrue);
      expect(codesOf(v), contains('T_SHARE_RENORMALIZED'));
      final double sum = v.spec.impact
          .fold(0.0, (double a, ImpactShare s) => a + s.share);
      expect(sum, closeTo(1.0, 1e-9));
      expect(v.spec.impact.first.share, closeTo(0.5, 1e-9));
    });

    test('新维度标 ability 但没依据 → 降成 experience', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'ua_1',
              axisLabel: '关系',
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
        ),
        registry: registry,
      );
      expect(v.accepted, isTrue);
      expect(codesOf(v), contains('T_AXIS_DEMOTED'));
      expect(v.spec.impact.single.kind, AxisKind.experience);
      expect(v.spec.contributesExp, isFalse);
    });

    test('新维度带衰减依据 → 保留 ability，并提示"等实测"', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'ua_2',
              axisLabel: '关系',
              kind: AxisKind.ability,
              share: 1,
              decayTauDays: 45,
              decayCitation: '陪伴停止后关系满意度回落较慢（经验近似）',
            ),
          ],
        ),
        registry: registry,
      );
      expect(v.accepted, isTrue);
      expect(codesOf(v), contains('T_AXIS_PROVISIONAL'));
      expect(v.spec.impact.single.kind, AxisKind.ability);
    });

    test('已知维度的量纲以注册表为准（AI 说了不算）', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'strength',
              axisLabel: '体能',
              kind: AxisKind.experience,
              share: 1,
            ),
          ],
        ),
        registry: registry,
      );
      expect(codesOf(v), contains('T_AXIS_KIND_FIXED'));
      expect(v.spec.impact.single.kind, AxisKind.ability);
      expect(v.spec.impact.single.axisLabel, '体能');
    });

    test('份额为 0 的维度被丢掉', () {
      final QuantValidation v = validateQuantSpec(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'discipline',
              axisLabel: '自律',
              kind: AxisKind.ability,
              share: 1,
            ),
            ImpactShare(
              axisKey: 'relation',
              axisLabel: '关系',
              kind: AxisKind.experience,
              share: 0,
            ),
          ],
        ),
        registry: registry,
      );
      expect(codesOf(v), contains('T_SHARE_DROPPED'));
      expect(v.spec.impact.length, 1);
    });
  });

  group('doseFraction 出口', () {
    test('不超过 1.5', () {
      final QuantSpec spec = specOf(target: 10);
      expect(spec.doseFractionFor(100), QuantSpec.doseFractionCeiling);
    });

    test('负数与 NaN 归 0', () {
      final QuantSpec spec = specOf(target: 10);
      expect(spec.doseFractionFor(-3), 0);
      expect(spec.doseFractionFor(double.nan), 0);
    });

    test('半量按形状给（saturating 0.8 / log 0.585）', () {
      expect(specOf(target: 10, shape: const DoseShapeSpec(kind: DoseShape.saturating))
          .doseFractionFor(5), closeTo(0.8, 1e-6));
      expect(specOf(target: 10, shape: const DoseShapeSpec(kind: DoseShape.log))
          .doseFractionFor(5), closeTo(0.585, 1e-3));
    });
  });

  group('序列化', () {
    test('往返保持形状与维度', () {
      final QuantSpec spec = specOf(
        shape: const DoseShapeSpec(kind: DoseShape.log, logK: 2),
        impact: const <ImpactShare>[
          ImpactShare(
            axisKey: 'discipline',
            axisLabel: '自律',
            kind: AxisKind.ability,
            share: 1,
          ),
        ],
      );
      final QuantSpec? back = QuantSpec.fromJson(spec.toJson());
      expect(back, isNotNull);
      expect(back!.shape.kind, DoseShape.log);
      expect(back.shape.logK, 2);
      expect(back.impact.single.axisKey, 'discipline');
    });

    test('缺 measure_kind 直接返回 null（不猜）', () {
      final Map<String, Object?> broken = <String, Object?>{
        'behavior_code': 'custom_1',
      };
      expect(QuantSpec.fromJson(broken), isNull);
    });

    test('ratio 字段往返：0.5T 阈值', () {
      const QuantSpec spec = QuantSpec(
        behaviorCode: 'custom_2',
        measureKind: MeasureKind.episode,
        measureUnit: '次',
        shape: DoseShapeSpec(kind: DoseShape.threshold, thetaFraction: 0.5),
        targetDose: 2,
        impact: <ImpactShare>[
          ImpactShare(
            axisKey: 'discipline',
            axisLabel: '自律',
            kind: AxisKind.ability,
            share: 1,
          ),
        ],
      );
      final QuantSpec? back = QuantSpec.fromJson(spec.toJson());
      expect(back!.shape.thetaFraction, 0.5);
      expect(back.doseFractionFor(1), 1);
    });
  });
}
