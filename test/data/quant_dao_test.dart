/// 量化形状层的数据层验收。
///
/// 验的不是"代码能跑"，是"约束真的在库这一层生效"：
/// CHECK 挡非法形状与分母为 0、主键保证一个行为一条口径、
/// revision 每次改写 +1、坏行不会被静默回退成 linear。
library;

import 'package:exp_ledger/data/dao/quant_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/migrations.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;
  const QuantDao dao = QuantDao();

  setUp(() async {
    db = await openTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  QuantSpec specOf({
    String code = 'custom_1',
    DoseShapeSpec shape = const DoseShapeSpec.linear(),
    double target = 30,
    String source = 'userPrior',
  }) =>
      QuantSpec(
        behaviorCode: code,
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
        citation: '测试用',
        source: source,
      );

  group('建表', () {
    test('两张新表都在 Tables.all 里（清空数据会一起清）', () {
      expect(Tables.all, contains(Tables.behaviorQuantSpec));
      expect(Tables.all, contains(Tables.axisDefinition));
    });

    test('表与索引真的建好了', () async {
      expect(await tableExists(db, Tables.behaviorQuantSpec), isTrue);
      expect(await tableExists(db, Tables.axisDefinition), isTrue);
      expect(await indexExists(db, Indexes.axisDefinitionKind), isTrue);
    });
  });

  group('口径往返', () {
    test('形状、量法、来源、依据都能读回来', () async {
      await dao.upsertSpec(
        db.db,
        specOf(shape: const DoseShapeSpec(kind: DoseShape.log, logK: 2)),
        now: DateTime(2026, 3, 1),
      );

      final QuantSpec? back = await dao.specByCode(db.db, 'custom_1');
      expect(back, isNotNull);
      expect(back!.shape.kind, DoseShape.log);
      expect(back.shape.logK, 2);
      expect(back.measureKind, MeasureKind.durationMin);
      expect(back.measureUnit, '分钟');
      expect(back.targetDose, 30);
      expect(back.impact.single.axisKey, 'discipline');
      expect(back.impact.single.kind, AxisKind.ability);
      expect(back.citation, '测试用');
    });

    test('阈值的小数位不会在 REAL 里抖（0.5 仍等于 0.5）', () async {
      await dao.upsertSpec(
        db.db,
        specOf(shape: const DoseShapeSpec(kind: DoseShape.threshold, thetaFraction: 0.5)),
        now: DateTime(2026, 3, 1),
      );
      final QuantSpec? back = await dao.specByCode(db.db, 'custom_1');
      expect(back!.shape.thetaFraction, 0.5);
      expect(back.doseFractionFor(0), 0);
    });

    test('同一行为重复保存：仍一行，revision 递增，created_at 不变', () async {
      await dao.upsertSpec(db.db, specOf(), now: DateTime(2026, 3, 1));
      await dao.upsertSpec(db.db, specOf(), now: DateTime(2026, 3, 2));
      await dao.upsertSpec(db.db, specOf(), now: DateTime(2026, 3, 3));

      expect(await countRows(db, Tables.behaviorQuantSpec), 1);
      final List<Map<String, Object?>> rows =
          await db.db.query(Tables.behaviorQuantSpec);
      expect(rows.single['revision'], 3);
      expect(rows.single['created_at'], '2026-03-01T00:00:00.000');
      expect(rows.single['updated_at'], '2026-03-03T00:00:00.000');
    });

    test('删掉后查不到', () async {
      await dao.upsertSpec(db.db, specOf(), now: DateTime(2026, 3, 1));
      await dao.deleteSpec(db.db, 'custom_1');
      expect(await dao.specByCode(db.db, 'custom_1'), isNull);
      expect(await countRows(db, Tables.behaviorQuantSpec), 0);
    });
  });

  group('库层的硬约束（不是靠调用方自觉）', () {
    test('target_dose = 0 被库拒绝', () async {
      await expectLater(
        db.db.insert(Tables.behaviorQuantSpec, <String, Object?>{
          'behavior_code': 'bad',
          'measure_kind': 'count',
          'measure_unit': '次',
          'target_dose': 0.0,
          'created_at': '2026-03-01T00:00:00.000',
          'updated_at': '2026-03-01T00:00:00.000',
        }),
        throwsA(anything),
      );
    });

    test('白名单之外的形状被库拒绝', () async {
      await expectLater(
        db.db.insert(Tables.behaviorQuantSpec, <String, Object?>{
          'behavior_code': 'bad',
          'measure_kind': 'count',
          'measure_unit': '次',
          'shape_kind': 'biphasic',
          'target_dose': 1.0,
          'created_at': '2026-03-01T00:00:00.000',
          'updated_at': '2026-03-01T00:00:00.000',
        }),
        throwsA(anything),
      );
    });

    test('ability 维度没有衰减常数被库拒绝', () async {
      await expectLater(
        db.db.insert(Tables.axisDefinition, <String, Object?>{
          'axis_key': 'ua_bad',
          'label': '关系',
          'dim_kind': 'ability',
          'decay_tau_days': 0.0,
          'created_at': '2026-03-01T00:00:00.000',
          'updated_at': '2026-03-01T00:00:00.000',
        }),
        throwsA(anything),
      );
    });

    test('experience 维度不要求衰减常数', () async {
      await db.db.insert(Tables.axisDefinition, <String, Object?>{
        'axis_key': 'ua_ok',
        'label': '审美',
        'dim_kind': 'experience',
        'created_at': '2026-03-01T00:00:00.000',
        'updated_at': '2026-03-01T00:00:00.000',
      });
      expect(await countRows(db, Tables.axisDefinition), 1);
    });
  });

  group('迁移幂等（规则：同一个库被重复升级不会报错）', () {
    test('在已经 v5 的库上重跑 v4 → v5，不炸也不丢数据', () async {
      await dao.upsertSpec(db.db, specOf(), now: DateTime(2026, 3, 1));
      await Migrations.upgrade(db.db, from: 4, to: 5);
      expect(await countRows(db, Tables.behaviorQuantSpec), 1);
      expect(await tableExists(db, Tables.axisDefinition), isTrue);
    });

    test('从 v1 兜底升级到 v5，所有后加的表都在', () async {
      await Migrations.upgrade(db.db, from: 1, to: 5);
      expect(await tableExists(db, Tables.appSetting), isTrue);
      expect(await tableExists(db, Tables.userAnchor), isTrue);
      expect(await tableExists(db, Tables.customBehavior), isTrue);
      expect(await tableExists(db, Tables.behaviorQuantSpec), isTrue);
      expect(await tableExists(db, Tables.axisDefinition), isTrue);
    });
  });

  group('坏行不许静默变成 linear', () {
    test('measure_kind 不认识的行被跳过，而不是当成别的量法', () async {
      await db.db.insert(Tables.behaviorQuantSpec, <String, Object?>{
        'behavior_code': 'weird',
        'measure_kind': 'vibes',
        'measure_unit': '次',
        'target_dose': 1.0,
        'created_at': '2026-03-01T00:00:00.000',
        'updated_at': '2026-03-01T00:00:00.000',
      });
      final Map<String, QuantSpec> all = await dao.specs(db.db);
      expect(all, isEmpty);
      expect(await dao.specByCode(db.db, 'weird'), isNull);
    });

    test('impact_json 坏掉时口径仍在（维度为空，不会崩）', () async {
      await db.db.insert(Tables.behaviorQuantSpec, <String, Object?>{
        'behavior_code': 'broken_impact',
        'measure_kind': 'count',
        'measure_unit': '次',
        'target_dose': 1.0,
        'impact_json': 'not json',
        'created_at': '2026-03-01T00:00:00.000',
        'updated_at': '2026-03-01T00:00:00.000',
      });
      final QuantSpec? back = await dao.specByCode(db.db, 'broken_impact');
      expect(back, isNotNull);
      expect(back!.impact, isEmpty);
    });
  });

  group('自定义维度', () {
    const AxisSpec relation = AxisSpec(
      key: 'ua_1',
      label: '关系',
      kind: AxisKind.ability,
      decayTauDays: 45,
      decayCitation: '陪伴停止后回落较慢（经验近似）',
    );

    test('往返保持量纲与依据', () async {
      await dao.upsertAxis(db.db, relation, now: DateTime(2026, 3, 1));
      final AxisSpec? back = await dao.axisByKey(db.db, 'ua_1');
      expect(back, isNotNull);
      expect(back!.label, '关系');
      expect(back.kind, AxisKind.ability);
      expect(back.decayTauDays, 45);
      expect(back.decayCitation, contains('经验近似'));
    });

    test('experience 维度写库时 tau 强制 0', () async {
      await dao.upsertAxis(
        db.db,
        const AxisSpec(
          key: 'ua_2',
          label: '情绪',
          kind: AxisKind.experience,
          decayTauDays: 99,
        ),
        now: DateTime(2026, 3, 1),
      );
      final AxisSpec? back = await dao.axisByKey(db.db, 'ua_2');
      expect(back!.decayTauDays, 0);
    });

    test('同一 key 覆盖，不新增行，created_at 保留', () async {
      await dao.upsertAxis(db.db, relation, now: DateTime(2026, 3, 1));
      await dao.upsertAxis(db.db, relation, now: DateTime(2026, 3, 5));
      expect(await countRows(db, Tables.axisDefinition), 1);
      final List<Map<String, Object?>> rows =
          await db.db.query(Tables.axisDefinition);
      expect(rows.single['created_at'], '2026-03-01T00:00:00.000');
    });

    test('enabled = 0 的不出现在默认查询里', () async {
      await dao.upsertAxis(db.db, relation, now: DateTime(2026, 3, 1));
      await db.db.update(Tables.axisDefinition, <String, Object?>{'enabled': 0});
      expect(await dao.axes(db.db), isEmpty);
      expect((await dao.axes(db.db, enabledOnly: false)).length, 1);
    });

    test('注册表能合并进来', () async {
      await dao.upsertAxis(db.db, relation, now: DateTime(2026, 3, 1));
      final AxisRegistry registry = AxisRegistry(await dao.axes(db.db));
      expect(registry.all.length, 6);
      expect(registry.tryResolve('ua_1')?.label, '关系');
      expect(registry.tauFor('ua_1'), 45);
    });
  });
}
