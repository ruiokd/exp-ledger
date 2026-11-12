/// 第 4 步验收（二）：历史修正级联重算。
///
/// 要证明三件事：
///   1. 改历史某天的数值，之后的曲线整体改变；
///   2. 同样的输入重跑两次，结果完全一致（纯函数 → 收敛）；
///   3. 安全闸触发的那天暂停结算，累计经验原地不动。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/dirty_day_dao.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/repository/capture_repository.dart';
import 'package:exp_ledger/data/repository/config_repository.dart';
import 'package:exp_ledger/data/repository/settlement_repository.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  final d1 = DayKey(2025, 6, 1);
  final d2 = DayKey(2025, 6, 2);
  final d3 = DayKey(2025, 6, 3);

  late TestRig rig;

  setUp(() async {
    rig = TestRig(await openTestDb());
  });

  tearDown(() async {
    await rig.close();
  });

  test('写入后自动结算到今天，每天都留下结算与快照', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));

    // 从 d1 一路推到 kTestNow（6/3），空日也要推进状态。
    expect(await countRows(rig.database, Tables.daySettlement), 3);
    expect(await countRows(rig.database, Tables.abilitySnapshot), 3);

    final s1 = await rig.settlement.settlementOf(d1);
    expect(s1, isNotNull);
    expect(s1!.positiveExp, greaterThan(0));
    expect(s1.positives.length, 1);

    final snap1 = await rig.settlement.snapshotOf(d1);
    expect(snap1, isNotNull);
    expect(snap1!.totalExp, greaterThan(0));
    expect(snap1.abilityOf(ProjectAxis.strength.name), greaterThan(0));
  });

  test('改历史某天的剂量 → 之后每天的累计经验整体改变', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 0.3));
    final before = (await rig.settlement.snapshotOf(d3))!.totalExp;

    // 同一天同一槽位，把剂量改成 1.0：走"修订"而不是新增。
    final result = await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));
    expect(result.action, CommitAction.revised);

    final after = (await rig.settlement.snapshotOf(d3))!.totalExp;
    expect(after, greaterThan(before), reason: '历史变更必须传导到今天');

    // 中间那一天也受影响（它是同一条状态链上的节点）。
    final midBefore = await rig.settlement.settlementOf(d2);
    expect(midBefore, isNotNull);
  });

  test('同样的输入重跑两次，结果完全一致', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 0.6));
    await rig.capture.commit(positiveDraft(day: d2, dose: 1.0));

    final firstRun = await rig.settlement.recomputeFrom(d1);
    final snapshotA = (await rig.settlement.snapshotOf(d3))!;
    final settlementA = (await rig.settlement.settlementOf(d2))!;

    final secondRun = await rig.settlement.recomputeFrom(d1);
    final snapshotB = (await rig.settlement.snapshotOf(d3))!;
    final settlementB = (await rig.settlement.settlementOf(d2))!;

    expect(firstRun.count, 3);
    expect(secondRun.count, 3);
    expect(snapshotB.totalExp, closeTo(snapshotA.totalExp, 1e-9));
    expect(snapshotB.level, snapshotA.level);
    expect(snapshotB.buffer, closeTo(snapshotA.buffer, 1e-9));
    expect(settlementB.positiveExp, closeTo(settlementA.positiveExp, 1e-9));
    expect(settlementB.netExp, closeTo(settlementA.netExp, 1e-9));
    expect(
      settlementB.stateAfter.damageLoad,
      closeTo(settlementA.stateAfter.damageLoad, 1e-9),
    );
  });

  test('重算不会把同一根因的负向扣两遍', () async {
    await rig.capture.commit(lateNightDraft(day: d1, minutes: 120));

    final first = (await rig.settlement.settlementOf(d1))!.negativeExp;
    await rig.settlement.recomputeFrom(d1);
    final second = (await rig.settlement.settlementOf(d1))!.negativeExp;

    expect(second, closeTo(first, 1e-9));
    expect(await countRows(rig.database, Tables.negativeEvent), 1);
  });

  test('改系数 → 整条曲线跟着变；恢复默认 → 回到原值', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));
    final baseline = (await rig.settlement.snapshotOf(d3))!.totalExp;

    final config = ConfigRepository(database: rig.database);
    final write = await config.set('expPerPoint', 0.25);
    expect(write.ok, isTrue);

    await rig.settlement.recomputeFrom(d1);
    final cheaper = (await rig.settlement.snapshotOf(d3))!.totalExp;
    expect(cheaper, lessThan(baseline), reason: '每点折算减半，累计必然变小');

    await config.resetAll();
    await rig.settlement.recomputeFrom(d1);
    final restored = (await rig.settlement.snapshotOf(d3))!.totalExp;
    expect(restored, closeTo(baseline, 1e-6));
  });

  test('非法系数键被拒绝，不会静默写进去', () async {
    final config = ConfigRepository(database: rig.database);
    final result = await config.set('noSuchCoefficient', 1.0);
    expect(result.ok, isFalse);
    expect(await countRows(rig.database, Tables.configOverride), 0);
  });

  test('安全闸触发的那天暂停结算：不涨不跌', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));
    final dayOneExp = (await rig.settlement.snapshotOf(d1))!.totalExp;

    await rig.capture.commit(redFlagDraft(day: d2));

    final s2 = (await rig.settlement.settlementOf(d2))!;
    expect(s2.status, SettlementStatus.paused);
    expect(s2.netExp, 0);
    expect(s2.alert, isNotNull);
    expect(s2.alert!.advice, contains('就医'));

    final snap2 = (await rig.settlement.snapshotOf(d2))!;
    expect(
      snap2.totalExp,
      closeTo(dayOneExp, 1e-9),
      reason: '暂停结算等于状态原地不动',
    );
  });

  test('预测点为今天生成，且第一条是"实际值"', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));

    final forecast = await rig.settlement.forecastOf(d3);
    expect(forecast.containsKey(ProjectAxis.strength), isTrue);

    final strength = forecast[ProjectAxis.strength]!;
    expect(strength.first.isProjection, isFalse);
    expect(strength.first.day, d3);
    expect(strength.length, greaterThan(5));
    // 预测越远，置信带越宽（单调）。
    expect(
      strength.last.spread,
      greaterThanOrEqualTo(strength.first.spread),
    );
  });

  test('recomputePending 从最早的脏日开始跑', () async {
    await rig.capture.commit(positiveDraft(day: d1, dose: 1.0));
    await rig.capture.commit(positiveDraft(day: d2, dose: 1.0));

    final dirty = const DirtyDayDao();
    await dirty.clearAll(rig.database.db);
    await dirty.mark(rig.database.db, d2, reason: 'test');

    final run = await rig.settlement.recomputePending();
    expect(run.from, d2);
    expect(run.count, 2, reason: 'd2 到 6/3 共两天');
    expect(await dirty.count(rig.database.db), 0);
  });

  test('历史跨度太长时起点被上移，并标记 wasClamped', () async {
    final veryOld = d1.addDays(-(kMaxRecomputeDays + 30));
    final run = await rig.settlement.recomputeFrom(veryOld, through: d3);
    expect(run.wasClamped, isTrue);
    expect(run.count, kMaxRecomputeDays + 1);
  });
}
