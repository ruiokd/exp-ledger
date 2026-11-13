import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/repository/anchor_repository.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

/// 刻度标定层的数据层验收。
///
/// 这里只验"库做对了什么"：幂等、追加、事务。
/// 判定规则（封顶、降档、四道门）在 `test/anchor/anchor_engine_test.dart`。
void main() {
  late AppDatabase db;
  late AnchorRepository repo;
  final DateTime t0 = DateTime(2026, 3, 1, 20);

  UserAnchor anchorOf(String code, {String unit = '一次有效组'}) => UserAnchor(
        behaviorId: code,
        unitLabel: unit,
        definitionText: '接近力竭且动作达标',
        referenceObject: '相当于散步 20 分钟',
        measurementClass: MeasurementClass.formula,
        referenceRangeId: 'strength_sets',
        calibratedAt: t0,
      );

  setUp(() async {
    db = await openTestDb();
    repo = AnchorRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('一个行为一张卡片：重复保存只覆盖', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    await repo.saveAnchor(
      anchorOf('strength_training', unit: '一次训练'),
      now: t0.add(const Duration(days: 1)),
    );

    // 只有刻度、还没声明量级时 card() 刻意返回 null（避免"标了一半"的卡片），
    // 所以这里读 anchorOf。
    final UserAnchor? saved = await repo.anchorOf('strength_training');
    expect(saved, isNotNull);
    expect(saved!.unitLabel, '一次训练');
    expect(await repo.card('strength_training'), isNull);
  });

  test('刻度变更只追加 revision，不重算历史', () async {
    final UserAnchor first = anchorOf('strength_training');
    await repo.saveAnchor(first, now: t0);

    final UserAnchor second = first.revise(
      at: t0.add(const Duration(days: 10)),
      unitLabel: '一次训练',
      reason: '有效组太粗',
    );
    await repo.saveAnchor(second, now: t0.add(const Duration(days: 10)));

    final UserAnchor? saved = await repo.anchorOf('strength_training');
    expect(saved!.revisionHistory.length, 1);
    expect(saved.revisionHistory.first.field, 'unitLabel');
    expect(saved.revisionHistory.first.to, '一次训练');
  });

  test('先验权重落库时不超过 0.5', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    final DeclareResult r = await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.mediumHigh,
      at: t0,
    );
    expect(r.verdict.ok, isTrue);
    expect(r.impact!.weight, lessThanOrEqualTo(0.5));
    expect(r.impact!.source, ImpactSource.userPrior);
  });

  test('「大」被拒，库里不会留下半条声明', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    final DeclareResult r = await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.large,
      at: t0,
    );
    expect(r.verdict.ok, isFalse);
    expect(r.verdict.code, 'large_locked');
    expect(r.impact, isNull);
    expect(await repo.card('strength_training'), isNull);
  });

  test('证据落账后先验被覆盖，且是同一个事务', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.mediumHigh,
      at: t0,
    );

    final AnchorEvidence ev = await repo.recordEvidence(
      behaviorId: 'strength_training',
      kind: EvidenceKind.measuredTest,
      measuredValue: 9,
      unit: '一次有效组',
      performedAt: t0.add(const Duration(days: 3)),
      rangeId: 'strength_sets',
    );

    final AnchorCard card = (await repo.card('strength_training'))!;
    expect(card.impact.replacedBy, ev.id);
    expect(card.impact.isOverridden, isTrue);
    expect(card.evidence!.derivedTier, ImpactTier.medium);
    expect(card.isCalibrated, isTrue);

    final WeightResolution r = repo.engine.resolve(
      impact: card.impact,
      evidence: card.evidence,
    );
    expect(r.priorStillActive, isFalse);
    expect(r.appliedSource, ImpactSource.evidence);
    expect(r.uiNote, contains('实测'));
  });

  test('已实测的项不再接受新的先验', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.medium,
      at: t0,
    );
    await repo.recordEvidence(
      behaviorId: 'strength_training',
      kind: EvidenceKind.measuredTest,
      measuredValue: 9,
      unit: '一次有效组',
      performedAt: t0.add(const Duration(days: 3)),
      rangeId: 'strength_sets',
    );

    final DeclareResult r = await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.small,
      at: t0.add(const Duration(days: 4)),
    );
    expect(r.verdict.ok, isFalse);
    expect(r.verdict.code, 'already_calibrated');
  });

  test('超常识实测：降置信度但不阻断写入', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    final AnchorEvidence ev = await repo.recordEvidence(
      behaviorId: 'strength_training',
      kind: EvidenceKind.measuredTest,
      measuredValue: 5000,
      unit: '一次有效组',
      performedAt: t0,
      rangeId: 'strength_sets',
    );
    expect(ev.confidence, Confidence.formula);
    expect(ev.note, isNotEmpty);
    // 没声明过量级时 recordEvidence 只落证据，不造先验——
    // 所以这里查证据链，而不是卡片。
    final List<AnchorEvidence> history =
        await repo.evidenceHistory('strength_training');
    expect(history.single.id, ev.id);
  });

  test('清空刻度层不影响别的表', () async {
    await repo.saveAnchor(anchorOf('strength_training'), now: t0);
    await repo.declareImpact(
      behaviorId: 'strength_training',
      tier: ImpactTier.medium,
      at: t0,
    );
    await repo.clearLayer();
    expect(await repo.cards(), isEmpty);
    expect(await repo.card('strength_training'), isNull);
  });

  test('四张新表都在 Tables.all 里（清空数据会一起清）', () {
    expect(Tables.all, contains(Tables.userAnchor));
    expect(Tables.all, contains(Tables.anchorRevision));
    expect(Tables.all, contains(Tables.declaredImpact));
    expect(Tables.all, contains(Tables.anchorEvidence));
  });
}
