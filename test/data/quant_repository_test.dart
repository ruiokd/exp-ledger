/// 量化口径仓储：写入前的四道闸 + 与自建项目的同事务联动。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/repository/custom_behavior_repository.dart';
import 'package:exp_ledger/data/repository/quant_repository.dart';
import 'package:exp_ledger/domain/anchor/anchor_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/custom_behavior_def.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;
  late QuantRepository repo;

  setUp(() async {
    db = await openTestDb();
    repo = QuantRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  QuantSpec specOf({
    String code = 'custom_1',
    DoseShapeSpec shape = const DoseShapeSpec.linear(),
    List<ImpactShare>? impact,
    double target = 30,
  }) =>
      QuantSpec(
        behaviorCode: code,
        measureKind: MeasureKind.durationMin,
        measureUnit: '分钟',
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
        citation: '测试用',
      );

  group('保存：闸在前面，库在后面', () {
    test('合格的口径写进去了', () async {
      final QuantValidation v = await repo.save(specOf());
      expect(v.accepted, isTrue, reason: v.issues.toString());
      expect((await repo.specs()).length, 1);
      expect((await repo.specFor('custom_1'))?.targetDose, 30);
    });

    test('形状参数自由 → 一条都不写', () async {
      final QuantValidation v = await repo.save(
        specOf(shape: const DoseShapeSpec(kind: DoseShape.log, logK: 0.37)),
      );
      expect(v.accepted, isFalse);
      expect(await repo.specs(), isEmpty);
    });

    test('新维度没依据 → 降成体验维度后仍然写进去（T_ 不是拒收）', () async {
      final QuantValidation v = await repo.save(
        specOf(
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'ua_9',
              axisLabel: '关系',
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
        ),
      );
      expect(v.accepted, isTrue);
      final QuantSpec? back = await repo.specFor('custom_1');
      expect(back!.impact.single.kind, AxisKind.experience);
      expect(back.contributesExp, isFalse);
    });

    test('同一个行为改两次口径 → 仍一条，revision 到 2', () async {
      await repo.save(specOf());
      await repo.save(
        specOf(shape: const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
      );
      expect((await repo.specs()).length, 1);
      final QuantSpec? back = await repo.specFor('custom_1');
      expect(back!.shape.kind, DoseShape.log);
    });
  });

  group('维度：能力维度必须有衰减依据', () {
    test('experience 维度能建', () async {
      final AxisSpec? axis = await repo.createAxis(label: '关系');
      expect(axis, isNotNull);
      expect(axis!.kind, AxisKind.experience);
      expect((await repo.registry()).tryResolve(axis.key)?.label, '关系');
    });

    test('ability 维度没依据 → 拒绝，库里什么也没有', () async {
      final AxisSpec? axis = await repo.createAxis(
        label: '关系',
        kind: AxisKind.ability,
      );
      expect(axis, isNull);
      expect((await repo.registry()).userAxes, isEmpty);
    });

    test('ability 维度带依据 → 建成功，tau 留在注册表里', () async {
      final AxisSpec? axis = await repo.createAxis(
        label: '关系',
        kind: AxisKind.ability,
        decayTauDays: 45,
        decayCitation: '陪伴停止后关系满意度回落较慢（经验近似）',
      );
      expect(axis, isNotNull);
      expect((await repo.registry()).tauFor(axis!.key), 45);
    });

    test('空 label 与超长 label 都拒绝', () async {
      expect(await repo.createAxis(label: '   '), isNull);
      expect(await repo.createAxis(label: '一二三四五六七八九十十一十二三'), isNull);
    });

    test('还被口径引用着的维度不许删', () async {
      final AxisSpec? axis = await repo.createAxis(label: '关系');
      await repo.save(
        specOf(
          impact: <ImpactShare>[
            ImpactShare(
              axisKey: axis!.key,
              axisLabel: axis.label,
              kind: AxisKind.experience,
              share: 1,
            ),
          ],
        ),
      );
      expect(await repo.removeAxis(axis.key), isFalse);
      expect((await repo.registry()).tryResolve(axis.key), isNotNull);
    });

    test('没人用的维度能删', () async {
      final AxisSpec? axis = await repo.createAxis(label: '审美');
      expect(await repo.removeAxis(axis!.key), isTrue);
      expect((await repo.registry()).tryResolve(axis.key), isNull);
    });
  });

  group('与自建项目同事务', () {
    test('建项目就有一条 linear 基线口径，量纲取内置维度', () async {
      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '上一堂课',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.formula,
        unitLabel: '一节课',
        definitionText: '完整上完 45 分钟的课',
        targetDose: 45,
        doseUnit: '分钟',
        tier: ImpactTier.medium,
      );

      final QuantSpec? spec = await repo.specFor(record.code);
      expect(spec, isNotNull);
      expect(spec!.shape.kind, DoseShape.linear);
      expect(spec.measureKind, MeasureKind.durationMin);
      expect(spec.measureUnit, '分钟');
      expect(spec.targetDose, 45);
      expect(spec.impact.single.axisKey, 'discipline');
      expect(spec.contributesExp, isTrue);
      // 线性口径下做一半就是一半——与 v1.1.3 的行为完全一致。
      expect(spec.doseFractionFor(22.5), closeTo(0.5, 1e-9));
    });

    test('改口径后行为定义跟着变：linear 0.5 → log 0.631', () async {
      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '上一堂课',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.formula,
        unitLabel: '一节课',
        definitionText: '完整上完 45 分钟的课',
        targetDose: 40,
        doseUnit: '分钟',
        tier: ImpactTier.medium,
      );

      double fractionOf(BehaviorDef def) => def
          .derive(
            DeriveContext(
              answers: const <String, Object?>{'dose': 20},
              profile: const UserProfile(),
              config: kDefaultConfig,
              now: DateTime(2026, 3, 2),
            ),
          )
          .doseFraction;

      final BehaviorDef before =
          customBehaviorDef(record, quant: await repo.specFor(record.code));
      expect(fractionOf(before), closeTo(0.5, 1e-9));

      await repo.save(specOf(
        code: record.code,
        target: 40,
        shape: const DoseShapeSpec(kind: DoseShape.log, logK: 2),
      ));

      final BehaviorDef after =
          customBehaviorDef(record, quant: await repo.specFor(record.code));
      expect(fractionOf(after), closeTo(0.631, 1e-3));
    });

    test('建项目时手选事件型 → 库里那条口径就是 threshold', () async {
      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '看一场电影',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.subjective,
        unitLabel: '一次电影',
        definitionText: '从片头到片尾，中途不刷手机',
        targetDose: 1,
        doseUnit: '次',
        tier: ImpactTier.medium,
        quant: QuantSpec(
          behaviorCode: 'pending',
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
          citation: '事件型：要么发生要么没发生',
        ),
      );

      final QuantSpec? spec = await repo.specFor(record.code);
      expect(spec, isNotNull);
      expect(spec!.shape.kind, DoseShape.threshold);
      expect(spec.measureKind, MeasureKind.episode);
      expect(spec.behaviorCode, record.code, reason: '占位 code 必须被正式 code 覆盖');
      expect(spec.doseFractionFor(0.5), 0);
      expect(spec.doseFractionFor(1), 1);
    });

    test('口径挂用户自建维度时，不会被降成体验维度', () async {
      final AxisSpec? relation = await repo.createAxis(
        label: '关系',
        kind: AxisKind.ability,
        decayTauDays: 45,
        decayCitation: '陪伴停止后关系满意度回落较慢（经验近似）',
      );
      expect(relation, isNotNull);

      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '陪家人吃饭',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.subjective,
        unitLabel: '一顿饭',
        definitionText: '坐着吃完，不看手机',
        targetDose: 30,
        doseUnit: '分钟',
        tier: ImpactTier.medium,
        quant: QuantSpec(
          behaviorCode: 'pending',
          measureKind: MeasureKind.durationMin,
          measureUnit: '分钟',
          shape: const DoseShapeSpec(kind: DoseShape.saturating),
          targetDose: 30,
          impact: <ImpactShare>[
            ImpactShare(
              axisKey: relation!.key,
              axisLabel: relation.label,
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
        ),
      );

      final QuantSpec? spec = await repo.specFor(record.code);
      expect(spec!.impact.single.kind, AxisKind.ability,
          reason: '用户维度在库里已经登记，不该再被当成未知维度降级');
      expect(spec.contributesExp, isTrue);
      expect(spec.shape.kind, DoseShape.saturating);
    });

    test('手选一个自由参数（k=0.37）→ 退回线性，坏值不进库', () async {
      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '阅读',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.memory,
        measurementClass: MeasurementClass.formula,
        unitLabel: '一次阅读',
        definitionText: '连续读 30 分钟',
        targetDose: 30,
        doseUnit: '分钟',
        tier: ImpactTier.medium,
        quant: QuantSpec(
          behaviorCode: 'pending',
          measureKind: MeasureKind.durationMin,
          measureUnit: '分钟',
          shape: const DoseShapeSpec(kind: DoseShape.log, logK: 0.37),
          targetDose: 30,
          impact: const <ImpactShare>[
            ImpactShare(
              axisKey: 'memory',
              axisLabel: '词汇',
              kind: AxisKind.ability,
              share: 1,
            ),
          ],
        ),
      );

      final QuantSpec? spec = await repo.specFor(record.code);
      expect(spec!.shape.kind, DoseShape.linear);
      expect(spec.shape.logK, 1);
    });

    test('删项目把口径一起删掉（不留孤儿行）', () async {
      final CustomBehaviorRepository custom =
          CustomBehaviorRepository(database: db);
      final record = await custom.create(
        name: '陪孩子写作业',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.subjective,
        unitLabel: '一次',
        definitionText: '从坐下到收本子',
        targetDose: 1,
        doseUnit: '次',
        tier: ImpactTier.small,
      );
      expect(await repo.specFor(record.code), isNotNull);

      await custom.remove(record.code);
      expect(await repo.specFor(record.code), isNull);
    });
  });
}
