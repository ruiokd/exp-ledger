/// 分水岭：`customBehaviorDef` 从「写死的 dose/target」改成「读库里的口径」。
///
/// 这一组测试守三件事：
///   1. 没有口径行时，行为与 v1.1.x **逐字等价**（历史记录不受影响）；
///   2. 换形状之后，只有"没做满"那一段变，满分线仍在目标量处；
///   3. 口径改了要能原地换掉行为定义（`BehaviorLibrary.replace`）。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/domain/anchor/anchor_models.dart';
import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/custom_behavior_def.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:test/test.dart';

CustomBehaviorRecord recordOf({
  double targetDose = 40,
  String doseUnit = '分钟',
  String name = '上一堂课',
  ProjectAxis axis = ProjectAxis.discipline,
}) =>
    CustomBehaviorRecord(
      code: 'custom_1',
      name: name,
      category: BehaviorCategory.positive,
      axis: axis,
      measurementClass: MeasurementClass.formula,
      unitLabel: '一节课',
      definitionText: '完整上完 45 分钟的课',
      targetDose: targetDose,
      doseUnit: doseUnit,
      tier: ImpactTier.medium,
      createdAt: DateTime(2026, 3, 1),
    );

DerivedResult deriveWith(BehaviorDef def, double dose) => def.derive(
      DeriveContext(
        answers: <String, Object?>{'dose': dose},
        profile: const UserProfile(),
        config: kDefaultConfig,
        now: DateTime(2026, 3, 2, 19),
      ),
    );

QuantSpec specOf(DoseShapeSpec shape, {double target = 40}) => QuantSpec(
      behaviorCode: 'custom_1',
      measureKind: MeasureKind.durationMin,
      measureUnit: '分钟',
      shape: shape,
      targetDose: target,
      impact: const <ImpactShare>[
        ImpactShare(
          axisKey: 'discipline',
          axisLabel: '自律',
          kind: AxisKind.ability,
          share: 1,
        ),
      ],
      citation: '测试',
    );

void main() {
  final CustomBehaviorRecord record = recordOf();

  group('没有口径行 = v1.1.x 的行为', () {
    test('半量就是一半', () {
      final DerivedResult r = deriveWith(customBehaviorDef(record), 20);
      expect(r.doseFraction, closeTo(0.5, 1e-9));
    });

    test('超额仍按 1.5 封顶（与旧代码同一处封顶）', () {
      expect(deriveWith(customBehaviorDef(record), 60).doseFraction, 1.5);
      expect(deriveWith(customBehaviorDef(record), 400).doseFraction, 1.5);
    });

    test('0 与负数都是 0', () {
      expect(deriveWith(customBehaviorDef(record), 0).doseFraction, 0);
      expect(deriveWith(customBehaviorDef(record), -30).doseFraction, 0);
    });

    test('基线口径来自唯一的那一处定义', () {
      final QuantSpec baseline = linearBaselineFor(record);
      expect(baseline.shape.kind, DoseShape.linear);
      expect(baseline.targetDose, 40);
      expect(baseline.impact.single.axisKey, 'discipline');
      expect(baseline.measureKind, MeasureKind.durationMin);
    });
  });

  group('换形状：只改没做满那一段', () {
    test('对数 k=2：半量 0.631', () {
      final BehaviorDef def = customBehaviorDef(
        record,
        quant: specOf(const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
      );
      expect(deriveWith(def, 20).doseFraction, closeTo(0.631, 1e-3));
    });

    test('饱和：半量 0.8', () {
      final BehaviorDef def = customBehaviorDef(
        record,
        quant: specOf(const DoseShapeSpec(kind: DoseShape.saturating)),
      );
      expect(deriveWith(def, 20).doseFraction, closeTo(0.8, 1e-6));
    });

    test('三种形状在目标量处都还是 1.0', () {
      for (final DoseShapeSpec shape in <DoseShapeSpec>[
        const DoseShapeSpec.linear(),
        const DoseShapeSpec(kind: DoseShape.log, logK: 2),
        const DoseShapeSpec(kind: DoseShape.saturating),
      ]) {
        final BehaviorDef def =
            customBehaviorDef(record, quant: specOf(shape));
        expect(deriveWith(def, 40).doseFraction, closeTo(1.0, 1e-6),
            reason: shape.kind.name);
      }
    });

    test('事件型：一次电影，半场不算', () {
      final CustomBehaviorRecord film = recordOf(
        targetDose: 1,
        doseUnit: '次',
        name: '看一场电影',
      );
      final BehaviorDef def = customBehaviorDef(
        film,
        quant: QuantSpec(
          behaviorCode: film.code,
          measureKind: MeasureKind.episode,
          measureUnit: '次',
          shape: const DoseShapeSpec(kind: DoseShape.threshold),
          targetDose: 1,
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'discipline',
              axisLabel: '自律',
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
        ),
      );
      expect(deriveWith(def, 0.5).doseFraction, 0);
      expect(deriveWith(def, 1).doseFraction, 1);
    });

    test('回执里写着折算方式，用户看得见为什么只算六成', () {
      final BehaviorDef def = customBehaviorDef(
        record,
        quant: specOf(const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
      );
      final DerivedResult r = deriveWith(def, 20);
      final List<String> labels =
          r.lines.map((ReceiptLine l) => l.label).toList();
      expect(labels, contains('折算方式'));
      expect(r.normalized['shape'], 'log');
      expect(r.metrics['fraction'], closeTo(0.631, 1e-3));
    });
  });

  group('口径改了要换得掉（BehaviorLibrary.replace）', () {
    test('register 跳过已有 code，replace 覆盖它', () {
      final BehaviorLibrary library = BehaviorLibrary();
      library.register(<BehaviorDef>[customBehaviorDef(record)]);
      expect(deriveWith(library.require('custom_1'), 20).doseFraction,
          closeTo(0.5, 1e-9));

      // 只是再 register 一次：口径不会更新（这是 register 的语义，不是 bug）。
      library.register(<BehaviorDef>[
        customBehaviorDef(
          record,
          quant: specOf(const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
        ),
      ]);
      expect(deriveWith(library.require('custom_1'), 20).doseFraction,
          closeTo(0.5, 1e-9));

      // replace 才换得掉。
      library.replace(<BehaviorDef>[
        customBehaviorDef(
          record,
          quant: specOf(const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
        ),
      ]);
      expect(deriveWith(library.require('custom_1'), 20).doseFraction,
          closeTo(0.631, 1e-3));
    });

    test('replace 对不存在的 code 等价于新增，且不会重复', () {
      final BehaviorLibrary library = BehaviorLibrary();
      final int base = library.all.length;
      library.replace(<BehaviorDef>[customBehaviorDef(record)]);
      expect(library.all.length, base + 1);
      library.replace(<BehaviorDef>[customBehaviorDef(record)]);
      expect(library.all.length, base + 1);
    });
  });
}
