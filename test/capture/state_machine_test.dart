import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/capture/intent_matcher.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:test/test.dart';

/// 固定时钟，保证测试可重放。
DateTime fixedNow() => DateTime(2025, 6, 1, 22, 30);

CaptureMachine buildMachine({
  UserProfile? profile,
  Map<String, Object?>? Function(String)? lastAnswers,
}) {
  final library = BehaviorLibrary();
  return CaptureMachine(
    CaptureDeps(
      library: library,
      matcher: IntentMatcher(library),
      profile: () => profile ?? const UserProfile(weightKg: 72),
      config: () => kDefaultConfig,
      now: fixedNow,
      newSessionId: () => 'sess-test',
      lastAnswers: lastAnswers,
    ),
  );
}

/// 走完一道选择题。
CaptureState answer(CaptureMachine m, CaptureState s, String value) =>
    m.reduce(s, OptionPicked(value));

void main() {
  group('深蹲：完整走查', () {
    test('从一句话到回执，四步问答后产出正确中间量', () {
      final m = buildMachine();

      var s = m.reduce(const CaptureIdle(), const TextChanged('做了一组深蹲'));
      s = m.reduce(s, const SubmitIntent());
      expect(s, isA<CaptureDisambiguating>());

      final dis = s as CaptureDisambiguating;
      s = m.reduce(s, const CandidatePicked(0));
      // 抗阻训练需要先过计划门
      expect(s, isA<CapturePlanGate>());
      s = m.reduce(s, const PlanAnswered(PlanStatus.planned));
      expect(s, isA<CaptureQuestioning>());

      // exercise 已由意图匹配预填
      expect((s as CaptureQuestioning).answers['exercise'], 'squat');

      s = answer(m, s, 'barbell'); // 负重方式
      s = m.reduce(s, const NumberChanged(60)); // 重量
      s = m.reduce(s, const NumberChanged(12)); // 次数
      s = m.reduce(s, const NumberChanged(1)); // 组数
      s = answer(m, s, '4'); // RIR 3–4 → 强度 0.8
      s = answer(m, s, 'none'); // 无代偿

      expect(s, isA<CaptureReceipting>());
      final r = s as CaptureReceipting;
      final d = r.derived;

      expect(d.metrics['effective_sets'], closeTo(1.0, 1e-9));
      expect(d.metrics['intensity_factor'], 0.8);
      expect(d.metrics['volume_load'], 720);
      expect(d.metrics['kcal']!, closeTo(16.6, 0.6));
      expect(d.confidence, Confidence.selfReport);
      expect(r.valence, Valence.positive);
      expect(d.slotKey, 'squat');

      // 未确认前不产出 DraftEntry
      expect(s, isNot(isA<CaptureCommitted>()));

      s = m.reduce(s, const ConfirmReceipt());
      expect(s, isA<CaptureCommitted>());
      final entry = (s as CaptureCommitted).entry;
      expect(entry.answers['weight'], 60.0);
      expect(entry.idempotencyKey, '2025-06-01|strength_training|squat');
      expect(dis.candidates.first.behavior.code, 'strength_training');
    });

    test('同一份答案重复确认，幂等键完全相同（覆盖而非新增）', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('深蹲'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const PlanAnswered(PlanStatus.planned));
      s = answer(m, s, 'barbell');
      s = m.reduce(s, const NumberChanged(60));
      s = m.reduce(s, const NumberChanged(12));
      s = m.reduce(s, const NumberChanged(3));
      s = answer(m, s, '4');
      s = answer(m, s, 'none');
      final k1 = (m.reduce(s, const ConfirmReceipt()) as CaptureCommitted)
          .entry
          .idempotencyKey;
      final k2 = (m.reduce(s, const ConfirmReceipt()) as CaptureCommitted)
          .entry
          .idempotencyKey;
      expect(k1, k2);
    });

    test('自重深蹲不问重量，缺失的重量自动补默认值且不产生容量', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('自重深蹲'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const PlanAnswered(PlanStatus.planned));
      s = answer(m, s, 'bodyweight');
      final q = s as CaptureQuestioning;
      // load_type=bodyweight 后，重量题不可见，当前题应是"次数"
      expect(q.current?.id, 'reps');
      s = m.reduce(s, const NumberChanged(15));
      s = m.reduce(s, const NumberChanged(3));
      s = answer(m, s, '4');
      s = answer(m, s, 'none');
      final r = s as CaptureReceipting;
      expect(r.derived.metrics['weight_kg'], 0);
      expect(r.derived.metrics['volume_load'], 0);
      expect(r.derived.interpretation.contains('自重'), isTrue);
    });

    test('"不确定"会把置信度压到自报，但不阻塞流程', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('深蹲'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const PlanAnswered(PlanStatus.planned));
      s = answer(m, s, 'barbell');
      s = m.reduce(s, const NumberChanged(60));
      s = m.reduce(s, const NumberChanged(12));
      s = m.reduce(s, const NumberChanged(3));
      s = m.reduce(s, const MarkUnknown()); // RIR 不知道
      expect((s as CaptureQuestioning).ceiling, Confidence.selfReport);
      s = answer(m, s, 'none');
      expect(s, isA<CaptureReceipting>());
    });
  });

  group('背单词：完整走查', () {
    test('主动回忆 20 词，3 天保持率约 68%', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('背了20个单词'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      expect(s, isA<CaptureQuestioning>()); // 无需计划门
      s = answer(m, s, 'new');
      s = m.reduce(s, const NumberChanged(20));
      s = answer(m, s, 'active');
      s = answer(m, s, '3');
      s = answer(m, s, 'yes');
      final r = s as CaptureReceipting;
      expect(r.derived.metrics['retention_3d']!, closeTo(0.68, 0.02));
      expect(r.derived.metrics['consolidated_words']!, closeTo(13.6, 0.5));
      expect(r.valence, Valence.positive);
    });

    test('只看一遍的保持率显著低于主动回忆', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('背单词'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = answer(m, s, 'new');
      s = m.reduce(s, const NumberChanged(20));
      s = answer(m, s, 'passive');
      s = answer(m, s, '1');
      s = answer(m, s, 'no');
      final passive = (s as CaptureReceipting).derived.metrics['retention_3d']!;

      final m2 = buildMachine();
      CaptureState t = m2.reduce(const CaptureIdle(), const TextChanged('背单词'));
      t = m2.reduce(t, const SubmitIntent());
      t = m2.reduce(t, const CandidatePicked(0));
      t = answer(m2, t, 'new');
      t = m2.reduce(t, const NumberChanged(20));
      t = answer(m2, t, 'active');
      t = answer(m2, t, '1');
      t = answer(m2, t, 'yes');
      final active = (t as CaptureReceipting).derived.metrics['retention_3d']!;

      expect(active, greaterThan(passive));
    });
  });

  group('熬夜：完整走查', () {
    test('02:10 入睡，判为负向，睡眠缺口与熬夜分钟都正确', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('熬到两点才睡'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      expect(s, isA<CaptureQuestioning>());
      s = m.reduce(s, const TimePicked('02:10'));
      s = m.reduce(s, const TimePicked('07:00'));
      s = answer(m, s, '1'); // 醒 1 次
      s = answer(m, s, 'bad');

      final r = s as CaptureReceipting;
      expect(r.valence, Valence.negative);
      expect(r.derived.metrics['late_minutes'], 110);
      expect(r.derived.metrics['effective_hours']!, closeTo(4.63, 0.02));
      expect(r.derived.metrics['gap_hours']!, closeTo(2.87, 0.02));
      expect(r.derived.metrics['exp_sign'], -1);
      // 负向回执必须带上预计扣分
      expect(
        r.derived.lines.any((l) => l.label == '预计扣分'),
        isTrue,
      );
    });

    test('23:00 入睡且睡够，判为正向', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('昨晚睡觉'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const TimePicked('23:00'));
      s = m.reduce(s, const TimePicked('07:00'));
      s = answer(m, s, '0');
      s = answer(m, s, 'good');
      final r = s as CaptureReceipting;
      expect(r.valence, Valence.positive);
      expect(r.derived.metrics['late_minutes'], 0);
      expect(r.derived.metrics['gap_hours'], 0);
    });

    test('界线边缘：00:10 入睡不算熬夜', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('睡觉'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const TimePicked('00:10'));
      s = m.reduce(s, const TimePicked('07:20'));
      s = answer(m, s, '0');
      s = answer(m, s, 'ok');
      expect((s as CaptureReceipting).derived.metrics['late_minutes'], 0);
    });
  });

  group('流程韧性', () {
    test('无法匹配时不阻塞，落为自由记录', () {
      final m = buildMachine();
      final s = m.reduce(const CaptureIdle(), const TextChanged('今天有点奇怪'));
      expect(m.reduce(s, const SubmitIntent()), isA<CaptureFreeform>());
    });

    test('回执阶段点"改一下"回到第一题，答案仍在', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('背单词'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = answer(m, s, 'new');
      s = m.reduce(s, const NumberChanged(20));
      s = answer(m, s, 'active');
      s = answer(m, s, '1');
      s = answer(m, s, 'no');
      s = m.reduce(s, const EditReceipt());
      final q = s as CaptureQuestioning;
      expect(q.current?.id, 'mode');
      expect(q.answers['words'], 20.0);
    });

    test('上一步会回退一道题并清掉该题答案', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('背单词'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = answer(m, s, 'new');
      s = m.reduce(s, const NumberChanged(20));
      s = m.reduce(s, const StepBack());
      final q = s as CaptureQuestioning;
      expect(q.current?.id, 'words');
      expect(q.answers.containsKey('words'), isFalse);
    });

    test('"和上次一样"能一次填满所有已知题', () {
      final m = buildMachine(
        lastAnswers: (code) => code == 'vocabulary_review'
            ? {
                'mode': 'review',
                'words': 30.0,
                'method': 'active',
                'exposures': '3',
                'tested': 'yes',
              }
            : null,
      );
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('背单词'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const UseLastAnswers());
      expect(s, isA<CaptureReceipting>());
      expect((s as CaptureReceipting).derived.normalized['words'], 30);
    });

    test('合理性复核只提示不阻断：体重 3 倍以上的深蹲会给出提示', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('深蹲'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const PlanAnswered(PlanStatus.planned));
      s = answer(m, s, 'barbell');
      s = m.reduce(s, const NumberChanged(250));
      final q = s as CaptureQuestioning;
      expect(q.issues.any((i) => i.questionId == 'weight'), isTrue);
      // 依然可以继续
      s = m.reduce(s, const NumberChanged(200));
      expect(s, isA<CaptureQuestioning>());
    });

    test('计划外事件走独立通道，不直接产出正负分', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('临时加练'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = answer(m, s, 'sets');
      s = m.reduce(s, const NumberChanged(4));
      s = answer(m, s, 'tired');
      final r = s as CaptureReceipting;
      expect(r.valence, Valence.offPlan);
      expect(r.derived.metrics['offplan_kind'], 2); // 2 = 过量风险
    });
  });

  group('回执语言', () {
    test('负向回执不含惊叹号与评价词', () {
      final m = buildMachine();
      CaptureState s = m.reduce(const CaptureIdle(), const TextChanged('熬夜'));
      s = m.reduce(s, const SubmitIntent());
      s = m.reduce(s, const CandidatePicked(0));
      s = m.reduce(s, const TimePicked('03:00'));
      s = m.reduce(s, const TimePicked('06:30'));
      s = answer(m, s, '2');
      s = answer(m, s, 'bad');
      final r = s as CaptureReceipting;
      final all = r.derived.lines.map((l) => '${l.label}${l.value}').join();
      expect(all.contains('!'), isFalse);
      expect(all.contains('！'), isFalse);
      for (final bad in ['失败', '糟糕', '优秀', '自律不足']) {
        expect(all.contains(bad), isFalse);
      }
    });
  });

  test('未知值哨兵不会污染数值字段', () {
    final q = <String, Object?>{'a': kUnknownValue};
    expect(q.numOf('a'), isNull);
    expect(q.isUnknown('a'), isTrue);
  });
}
