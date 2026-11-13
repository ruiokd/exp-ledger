import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:test/test.dart';

void main() {
  const OnboardingFlow flow = OnboardingFlow(AnchorEngine());
  final DateTime now = DateTime(2026, 6, 1, 20);

  const List<OnboardingSelection> picked = <OnboardingSelection>[
    OnboardingSelection(
      behaviorId: 'strength.session',
      label: '力量训练',
      measurementClass: MeasurementClass.formula,
    ),
    OnboardingSelection(
      behaviorId: 'mind.deepTalk',
      label: '深谈',
      measurementClass: MeasurementClass.subjective,
    ),
    OnboardingSelection(
      behaviorId: 'chores.home',
      label: '家务',
      measurementClass: MeasurementClass.subjective,
    ),
  ];

  group('渐进式引导', () {
    test('第一步是选行为，且提示 3–5 项', () {
      const OnboardingState s = OnboardingState();
      final OnboardingPrompt p = flow.next(s);
      expect(p.kind, PromptKind.chooseBehaviors);
      expect(p.question, contains('3–5'));
      expect(p.options, isEmpty);
    });

    test('一次只问一件事：Step 2 只问单位，不问档位', () {
      final OnboardingState s = flow.pickBehaviors(
        const OnboardingState(),
        picked,
      );
      final OnboardingPrompt p = flow.next(s);
      expect(p.kind, PromptKind.defineUnit);
      expect(p.behaviorId, 'strength.session');
      expect(p.options.any((PromptOption o) => o.unitLabel != null), isTrue);
      expect(p.options.any((PromptOption o) => o.tier != null), isFalse);
      expect(p.footer, contains('不重算'));
    });

    test('第一项没有「同上次」，第二项才有', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      expect(flow.next(s).allowSameAsLast, isFalse);
      s = flow.defineUnit(s, at: now, unitLabel: '一次有效组');
      s = flow.declareTier(s, at: now, tier: ImpactTier.medium).state;
      expect(flow.next(s).allowSameAsLast, isTrue);
    });

    test('选行为有上限，超出被截断', () {
      final List<OnboardingSelection> many = <OnboardingSelection>[
        for (int i = 0; i < 9; i++)
          OnboardingSelection(
            behaviorId: 'b$i',
            label: '行为 $i',
            measurementClass: MeasurementClass.subjective,
          ),
      ];
      final OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), many);
      expect(s.selections.length, kDefaultAnchorConfig.maxBehaviors);
    });

    test('空单位不落账（但也不会卡死流程）', () {
      final OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      final OnboardingState after =
          flow.defineUnit(s, at: now, unitLabel: '   ');
      expect(after.anchors, isEmpty);
      expect(after.stage, OnboardingStage.defineUnit);
    });

    test('Step 3 不给「大」以外的选择缺失，但「大」被标为需要实测', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      s = flow.defineUnit(
        s,
        at: now,
        unitLabel: '一次有效组',
        rangeId: 'strength_sets',
      );
      final OnboardingPrompt p = flow.next(s);
      expect(p.kind, PromptKind.declareTier);
      expect(p.referenceRange, isNotNull);
      final PromptOption largeOption = p.options
          .firstWhere((PromptOption o) => o.tier == ImpactTier.large);
      expect(largeOption.detail, contains('实测'));
      expect(p.footer, contains('不超过'));
    });

    test('选「大」被拒，状态不变', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      s = flow.defineUnit(s, at: now, unitLabel: '一次有效组');
      final ({OnboardingState state, TierChangeVerdict verdict}) r =
          flow.declareTier(s, at: now, tier: ImpactTier.large);
      expect(r.verdict.ok, isFalse);
      expect(r.verdict.code, 'large_locked');
      expect(r.state.impacts, isEmpty);
    });

    test('三项标完 → done，并给出 3 张卡片', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      for (int i = 0; i < 3; i++) {
        s = flow.defineUnit(s, at: now, unitLabel: '一次${i + 1}');
        s = flow.declareTier(s, at: now, tier: ImpactTier.medium).state;
      }
      expect(s.stage, OnboardingStage.done);
      expect(flow.next(s).kind, PromptKind.done);

      final List<AnchorCard> cards = flow.buildCards(s);
      expect(cards.length, 3);
      expect(cards.first.tierSummary, contains('先验'));
      expect(cards.first.unitSummary, contains('一次 = 一次1'));
      expect(cards.first.isCalibrated, isFalse);
    });

    test('中途退出：已标的保留，剩下走自由记录', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      s = flow.defineUnit(s, at: now, unitLabel: '一次有效组');
      s = flow.declareTier(s, at: now, tier: ImpactTier.medium).state;
      s = flow.abandon(s);

      expect(s.abandoned, isTrue);
      expect(s.anchors.length, 1);
      expect(flow.isCalibrated(s, 'strength.session'), isTrue);
      expect(flow.isCalibrated(s, 'mind.deepTalk'), isFalse);
      // 没标完也不挡记录：置信度就是自报，不会更低一档。
      expect(flow.recordConfidence('mind.deepTalk').name, 'selfReport');
    });

    test('状态可序列化往返（跨会话续接）', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      s = flow.defineUnit(s, at: now, unitLabel: '一次有效组');
      s = flow.declareTier(s, at: now, tier: ImpactTier.medium).state;

      final OnboardingState back = OnboardingState.fromJson(s.toJson());
      expect(back.stage, s.stage);
      expect(back.cursor, s.cursor);
      expect(back.selections.length, s.selections.length);
      expect(back.anchors['strength.session']?.unitLabel, '一次有效组');
      expect(back.impacts['strength.session']?.tier, ImpactTier.medium);
    });

    test('同上次：把上一项的单位搬过来', () {
      OnboardingState s =
          flow.pickBehaviors(const OnboardingState(), picked);
      s = flow.defineUnit(s, at: now, unitLabel: '一次有效组');
      s = flow.declareTier(s, at: now, tier: ImpactTier.medium).state;
      s = flow.defineUnit(s, at: now, sameAsLast: true);
      expect(s.anchors['mind.deepTalk']?.unitLabel, '一次有效组');
      expect(s.usedSameAsLast, isTrue);
    });
  });
}
