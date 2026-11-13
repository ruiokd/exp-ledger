import 'package:exp_ledger/domain/anchor/anchor.dart';
// domain 层零 Flutter 依赖 → 用纯 package:test，不需要模拟器。
import 'package:test/test.dart';

void main() {
  const AnchorEngine engine = AnchorEngine();
  const AnchorConfig config = kDefaultAnchorConfig;

  group('先验权重封顶', () {
    test('四档先验都不超过 0.5', () {
      for (final ImpactTier t in ImpactTier.values) {
        final double w = engine.priorWeightFor(
          tier: t,
          source: ImpactSource.userPrior,
        );
        expect(w, lessThanOrEqualTo(config.priorWeightCap));
        expect(w, greaterThan(0));
      }
    });

    test('「大」的声明值 0.60 被夹到 0.5', () {
      final double w = engine.priorWeightFor(
        tier: ImpactTier.large,
        source: ImpactSource.userPrior,
      );
      expect(w, 0.5);
    });

    test('AI 提议比用户自估更低', () {
      final double human = engine.priorWeightFor(
        tier: ImpactTier.mediumHigh,
        source: ImpactSource.userPrior,
      );
      final double ai = engine.priorWeightFor(
        tier: ImpactTier.mediumHigh,
        source: ImpactSource.aiProposal,
      );
      expect(ai, lessThan(human));
      expect(ai, lessThanOrEqualTo(config.priorWeightCap));
    });

    test('档位越高权重越高（单调）', () {
      double prev = -1;
      for (final ImpactTier t in ImpactTier.values) {
        final double w = engine.priorWeightFor(
          tier: t,
          source: ImpactSource.userPrior,
        );
        expect(w, greaterThanOrEqualTo(prev));
        prev = w;
      }
    });
  });

  group('可量化程度决定路径', () {
    test('仅主观可辨：EXP 权重为 0 且不能扣分', () {
      expect(engine.expWeightFor(MeasurementClass.subjective), 0);
      expect(engine.mayDeduct(MeasurementClass.subjective), isFalse);
    });

    test('半可观测：权重极小，不能扣分', () {
      final double w = engine.expWeightFor(MeasurementClass.semiObservable);
      expect(w, greaterThan(0));
      expect(w, lessThan(0.1));
      expect(engine.mayDeduct(MeasurementClass.semiObservable), isFalse);
      expect(engine.prefersTimeShare(MeasurementClass.semiObservable), isTrue);
    });

    test('可公式化：权重 1 且可扣分', () {
      expect(engine.expWeightFor(MeasurementClass.formula), 1.0);
      expect(engine.mayDeduct(MeasurementClass.formula), isTrue);
    });
  });

  group('档位调整的四道门', () {
    test('「大」没有实测证据 → 拒绝', () {
      final TierChangeVerdict v = engine.checkTierChange(
        to: ImpactTier.large,
        from: ImpactTier.mediumHigh,
        reason: '感觉很重要',
      );
      expect(v.ok, isFalse);
      expect(v.code, 'large_locked');
      expect(v.appliedTier, isNull);
    });

    test('「大」有实测证据 → 放行', () {
      final TierChangeVerdict v = engine.checkTierChange(
        to: ImpactTier.large,
        from: ImpactTier.medium,
        hasCalibratedEvidence: true,
      );
      expect(v.ok, isTrue);
    });

    test('一次跳两档 → 拒绝', () {
      final TierChangeVerdict v = engine.checkTierChange(
        to: ImpactTier.mediumHigh,
        from: ImpactTier.small,
        reason: '就是很重要',
      );
      expect(v.ok, isFalse);
      expect(v.code, 'jump_too_far');
    });

    test('往上调但不写理由 → 拒绝', () {
      final TierChangeVerdict v = engine.checkTierChange(
        to: ImpactTier.medium,
        from: ImpactTier.small,
      );
      expect(v.ok, isFalse);
      expect(v.code, 'reason_required');
    });

    test('往下调不需要理由', () {
      final TierChangeVerdict v = engine.checkTierChange(
        to: ImpactTier.small,
        from: ImpactTier.mediumHigh,
      );
      expect(v.ok, isTrue);
    });
  });

  group('先验 → 证据覆盖', () {
    final DateTime now = DateTime(2026, 3, 1);

    test('没有证据时先验生效并带空心标记', () {
      final DeclaredImpact impact = engine.declare(
        behaviorId: 'strength.session',
        tier: ImpactTier.mediumHigh,
        source: ImpactSource.userPrior,
        at: now,
      );
      final WeightResolution r = engine.resolve(impact: impact);
      expect(r.priorStillActive, isTrue);
      expect(r.effectiveWeight, impact.weight);
      expect(r.appliedSource, ImpactSource.userPrior);
      expect(r.marker.hollow, isTrue);
      expect(r.marker.dashed, isTrue);
      expect(r.marker.bandHalfWidth, greaterThan(0));
    });

    test('证据落账后先验权重归零、来源变成 evidence', () {
      final DeclaredImpact impact = engine.declare(
        behaviorId: 'strength.session',
        tier: ImpactTier.mediumHigh,
        source: ImpactSource.userPrior,
        at: now,
      );
      final AnchorEvidence ev = engine.buildEvidence(
        id: 'ev-1',
        behaviorId: 'strength.session',
        kind: EvidenceKind.measuredTest,
        measuredValue: 10,
        unit: '一次有效组',
        performedAt: now,
        range: referenceRangeById('strength_sets'),
      );
      final DeclaredImpact covered =
          engine.coverWithEvidence(impact: impact, evidence: ev);
      final WeightResolution r =
          engine.resolve(impact: covered, evidence: ev);

      expect(covered.isOverridden, isTrue);
      expect(covered.replacedBy, 'ev-1');
      expect(r.priorStillActive, isFalse);
      expect(r.appliedSource, ImpactSource.evidence);
      expect(r.effectiveWeight, config.tierMediumPrior);
      expect(r.uiNote, contains('实测'));
      expect(r.marker.hollow, isFalse);
    });

    test('有证据但没落账 → 仍然先验，并提示要落账', () {
      final DeclaredImpact impact = engine.declare(
        behaviorId: 'strength.session',
        tier: ImpactTier.medium,
        source: ImpactSource.userPrior,
        at: now,
      );
      final AnchorEvidence ev = engine.buildEvidence(
        id: 'ev-2',
        behaviorId: 'strength.session',
        kind: EvidenceKind.measuredTest,
        measuredValue: 8,
        unit: '一次有效组',
        performedAt: now,
        range: referenceRangeById('strength_sets'),
      );
      final WeightResolution r = engine.resolve(impact: impact, evidence: ev);
      expect(r.priorStillActive, isTrue);
      expect(r.uiNote, contains('coverWithEvidence'));
    });
  });

  group('实测反算档位', () {
    test('落在参照区间的对应档', () {
      final ReferenceRange r = referenceRangeById('strength_sets')!;
      expect(engine.tierFromRange(r, 3), ImpactTier.small);
      expect(engine.tierFromRange(r, 9), ImpactTier.medium);
      expect(engine.tierFromRange(r, 15), ImpactTier.mediumHigh);
      expect(engine.tierFromRange(r, 40), ImpactTier.large);
    });

    test('无参照区间时按「一次 = 1.0」的倍数', () {
      expect(engine.tierFromRatio(1.0), ImpactTier.medium);
      expect(engine.tierFromRatio(3.0), ImpactTier.large);
      expect(engine.tierFromRatio(0.2), ImpactTier.small);
    });

    test('超常识区间 → 降置信度但不阻断', () {
      final AnchorEvidence ev = engine.buildEvidence(
        id: 'ev-3',
        behaviorId: 'sleep.night',
        kind: EvidenceKind.bodyTrend,
        measuredValue: 900,
        unit: '小时',
        performedAt: DateTime(2026, 3, 2),
        range: referenceRangeById('sleep_hours'),
      );
      expect(ev.confidence.name, isNot('calibrated'));
      expect(ev.note, isNotEmpty);
      final SanityVerdict s = engine.sanityCheck(
        cls: MeasurementClass.formula,
        measured: 900,
        range: referenceRangeById('sleep_hours'),
      );
      expect(s.level, SanityLevel.implausible);
      expect(s.blocks, isFalse);
    });
  });

  group('文案与变更范围', () {
    test('估计高于实测时说明差几档', () {
      final String s = engine.divergenceSentence(
        declared: ImpactTier.mediumHigh,
        measured: ImpactTier.medium,
      );
      expect(s, contains('中偏大'));
      expect(s, contains('实测接近中'));
    });

    test('一致时给出「可以停了」', () {
      final String s = engine.divergenceSentence(
        declared: ImpactTier.medium,
        measured: ImpactTier.medium,
      );
      expect(s, contains('一致'));
    });

    test('刻度变更不追溯', () {
      final DateTime changed = DateTime(2026, 3, 10, 9);
      final RecomputeScope before =
          engine.scopeForAnchorChange(changedAt: changed, dayKey: '2026-03-09');
      final RecomputeScope after =
          engine.scopeForAnchorChange(changedAt: changed, dayKey: '2026-03-10');
      expect(before.usesNewScale, isFalse);
      expect(after.usesNewScale, isTrue);
      expect(before.mustMarkPoint, isTrue);
      expect(after.mustMarkPoint, isTrue);
    });

    test('改单位会追加 revision 与变更点', () {
      final DateTime t0 = DateTime(2026, 3, 1);
      final UserAnchor a = UserAnchor(
        behaviorId: 'writing.block',
        unitLabel: '完成段落',
        definitionText: '一口气写完一段且不再回头改',
        referenceObject: '相当于走路 10 分钟',
        measurementClass: MeasurementClass.formula,
        referenceRangeId: 'writing_output',
        calibratedAt: t0,
      );
      final UserAnchor b = a.revise(
        at: DateTime(2026, 4, 1),
        unitLabel: '字',
        definitionText: '新增的非重复正文',
        reason: '段落粒度太粗',
      );
      expect(b.revisionHistory.length, 2);
      expect(b.changePoints.length, 2);
      expect(b.unitLabel, '字');
      expect(a.unitLabel, '完成段落');
    });
  });
}
