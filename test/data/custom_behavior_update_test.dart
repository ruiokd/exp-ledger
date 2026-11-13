/// 编辑自建项目：两个真源（`custom_behavior.target_dose` 与
/// `behavior_quant_spec.target_dose`）必须同事务改。
///
/// 这条测试守的是 STATE 七里那句提醒：分开改会出现
/// "改了目标量但曲线没变"这种极难查的现象。
library;

import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/anchor/anchor_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:exp_ledger/data/repository/custom_behavior_repository.dart';
import 'package:exp_ledger/data/repository/quant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;
  late CustomBehaviorRepository custom;
  late QuantRepository quant;

  setUp(() async {
    db = await openTestDb();
    custom = CustomBehaviorRepository(database: db);
    quant = QuantRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<CustomBehaviorRecord> seed({
    double target = 40,
    String unit = '分钟',
  }) =>
      custom.create(
        name: '上一堂课',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.formula,
        unitLabel: '一节课',
        definitionText: '完整上完',
        targetDose: target,
        doseUnit: unit,
        tier: ImpactTier.medium,
      );

  QuantSpec quantOf(
    String code,
    DoseShape shape, {
    double target = 40,
    String unit = '分钟',
  }) =>
      QuantSpec(
        behaviorCode: code,
        measureKind: MeasureKind.durationMin,
        measureUnit: unit,
        shape: DoseShapeSpec(kind: shape),
        targetDose: target,
        impact: const <ImpactShare>[
          ImpactShare(
            axisKey: 'discipline',
            axisLabel: '自律',
            kind: AxisKind.ability,
            share: 1,
          ),
        ],
        citation: '编辑时选择',
      );

  test('改目标量：行为表与口径表一起改（两个真源）', () async {
    final CustomBehaviorRecord r = await seed(target: 40);
    await custom.update(code: r.code, targetDose: 20);

    final List<Map<String, Object?>> rows = await db.db.query(
      Tables.customBehavior,
      where: 'code = ?',
      whereArgs: <Object?>[r.code],
    );
    expect((rows.single['target_dose'] as num).toDouble(), 20);
    expect(rows.single['created_at'], isNotNull);

    final QuantSpec? spec = await quant.specFor(r.code);
    expect(spec!.targetDose, 20);
    expect(spec.shape.kind, DoseShape.linear, reason: '只改量不该顺手改形状');
    expect(spec.doseFractionFor(10), closeTo(0.5, 1e-9));
  });

  test('改折算方式：形状变了，目标量不动', () async {
    final CustomBehaviorRecord r = await seed(target: 40);
    await custom.update(
      code: r.code,
      quant: quantOf(r.code, DoseShape.saturating),
    );

    final QuantSpec? spec = await quant.specFor(r.code);
    expect(spec!.shape.kind, DoseShape.saturating);
    expect(spec.targetDose, 40);
    expect(spec.doseFractionFor(20), closeTo(0.8, 1e-6));
  });

  test('改名字只动名字（口径与目标量原样）', () async {
    final CustomBehaviorRecord r = await seed();
    final CustomBehaviorRecord? next =
        await custom.update(code: r.code, name: '上一节专业课');

    expect(next, isNotNull);
    expect(next!.name, '上一节专业课');
    expect(next.code, r.code, reason: '行为码永不改，改了就丢历史');
    expect(next.targetDose, 40);

    final QuantSpec? spec = await quant.specFor(r.code);
    expect(spec!.targetDose, 40);
  });

  test('空名字不改名字（不把用户清空的名字写进去）', () async {
    final CustomBehaviorRecord r = await seed();
    await custom.update(code: r.code, name: '   ');
    final CustomBehaviorRecord? back = await custom.byCode(r.code);
    expect(back!.name, '上一堂课');
  });

  test('手滑给了自由参数 k=0.37：保留旧口径，方法不抛', () async {
    final CustomBehaviorRecord r = await seed();
    await custom.update(
      code: r.code,
      quant: quantOf(r.code, DoseShape.log).copyWith(
        shape: const DoseShapeSpec(kind: DoseShape.log, logK: 0.37),
      ),
    );
    final QuantSpec? spec = await quant.specFor(r.code);
    expect(spec!.shape.kind, DoseShape.linear, reason: '坏口径不许覆盖好口径');
    expect(spec.contributesExp, isTrue);
  });

  test('改不存在的项目返回 null（不抛、不建新行）', () async {
    expect(await custom.update(code: 'custom_nope', targetDose: 10), isNull);
    expect(await countRows(db, Tables.customBehavior), 0);
    expect(await countRows(db, Tables.behaviorQuantSpec), 0);
  });

  test('编辑后 revision 递增（改一次口径留一次痕）', () async {
    final CustomBehaviorRecord r = await seed();
    await custom.update(code: r.code, targetDose: 30);
    await custom.update(code: r.code, targetDose: 20);

    final List<Map<String, Object?>> rows =
        await db.db.query(Tables.behaviorQuantSpec);
    expect(rows.single['revision'], 3, reason: '建 1 次 + 改 2 次');
  });
}
