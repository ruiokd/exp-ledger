import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/engine/attribution.dart';
import 'package:exp_ledger/domain/engine/efficiency_bonus.dart';
import 'package:exp_ledger/domain/engine/level_curve.dart';
import 'package:exp_ledger/domain/engine/overshoot_router.dart';
import 'package:exp_ledger/domain/engine/quality_bonus.dart';
import 'package:exp_ledger/domain/engine/safety_gate.dart';
import 'package:exp_ledger/domain/engine/score_curves.dart';
import 'package:exp_ledger/domain/engine/state_multiplier.dart';
import 'package:exp_ledger/domain/engine/valence_engine.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:test/test.dart';

const cfg = kDefaultConfig;
final day = DayKey(2025, 6, 1);

/// 造一条记录。测试里只关心引擎需要的那几个字段。
DraftEntry mk({
  String code = 'strength_training',
  Valence valence = Valence.positive,
  ProjectAxis axis = ProjectAxis.strength,
  double doseFraction = 1.0,
  Confidence confidence = Confidence.selfReport,
  PlanStatus plan = PlanStatus.planned,
  Map<String, double> metrics = const {},
  Map<String, Object?> answers = const {},
  bool interruption = false,
  DayKey? on,
}) {
  final d = on ?? day;
  return DraftEntry(
    dayKey: d,
    behaviorCode: code,
    category: valence == Valence.negative
        ? BehaviorCategory.negative
        : (valence == Valence.offPlan
            ? BehaviorCategory.offPlan
            : BehaviorCategory.positive),
    valence: valence,
    axis: axis,
    planStatus: plan,
    confidence: confidence,
    slotKey: 'slot',
    answers: answers,
    metrics: metrics,
    interpretation: code,
    doseFraction: doseFraction,
    source: 'test',
    createdAt: DateTime(2025, 6, 1, 12),
    isInterruption: interruption,
  );
}

EngineContext ctxOf({
  StateVars state = StateVars.zero,
  AcwrBand band = AcwrBand.low,
  Set<String> keys = const {},
  double baseline = 0,
  int hoursSince = 999,
  bool fatigued = false,
}) =>
    EngineContext(
      dayKey: day,
      state: state,
      config: cfg,
      nextBand: band,
      existingRootKeys: keys,
      baselineEfficiency: baseline,
      hoursSinceSameMuscle: hoursSince,
      fatigued: fatigued,
    );

void main() {
  group('熬夜扣分曲线（非线性加速）', () {
    test('轻微越界扣得很少：30 分钟 = 0.12 单位', () {
      expect(cfg.negativeDoseCurve(30), closeTo(0.12, 1e-9));
    });

    test('越界越深，边际成本越高（凸性）', () {
      final d1 = cfg.negativeDoseCurve(60) - cfg.negativeDoseCurve(30);
      final d2 = cfg.negativeDoseCurve(120) - cfg.negativeDoseCurve(90);
      expect(d2, greaterThan(d1 * 1.2));
    });

    test('单调不减，且 0 剂量不扣分', () {
      expect(cfg.negativeDoseCurve(0), 0);
      var prev = 0.0;
      for (var m = 0; m <= 300; m += 10) {
        final v = cfg.negativeDoseCurve(m.toDouble());
        expect(v, greaterThanOrEqualTo(prev));
        prev = v;
      }
    });

    test('超过 2 小时进入陡增区：180 分钟 > 120 分钟 × 1.1', () {
      expect(cfg.negativeDoseCurve(180),
          greaterThan(cfg.negativeDoseCurve(120) * 1.1));
    });

    test('110 分钟熬夜 ≈ −2.9 EXP', () {
      final exp = cfg.negativeDoseExp(110);
      expect(exp, closeTo(-2.94, 0.05));
      expect(exp, lessThan(0));
    });
  });

  group('睡眠负债对次日加分的打折', () {
    test('负债 0 小时不打折', () {
      expect(cfg.sleepMultiplier(0), 1.0);
    });

    test('负债 2.87 小时 → 乘数 0.857', () {
      expect(cfg.sleepMultiplier(2.867), closeTo(0.8566, 0.001));
    });

    test('折价有上限 35%，不会把努力归零', () {
      expect(cfg.sleepMultiplier(20), closeTo(0.65, 1e-9));
      expect(cfg.sleepMultiplier(100), closeTo(0.65, 1e-9));
    });

    test('组合乘数有 0.30 下限', () {
      final m = multipliersFor(const StateVars(
        sleepDebtHours: 40,
        damageLoad: 100,
        recoveryDebt: 100,
      ));
      expect(m.combined, closeTo(0.30, 1e-9));
    });

    test('同样的记录，负债高时经验更少', () {
      final low = const ValenceEngine().evaluate(
        mk(metrics: {'effective_sets': 3.0, 'session_minutes': 12.0}),
        ctxOf(),
      );
      final high = const ValenceEngine().evaluate(
        mk(metrics: {'effective_sets': 3.0, 'session_minutes': 12.0}),
        ctxOf(state: const StateVars(sleepDebtHours: 4)),
      );
      expect(high.positive!.exp, lessThan(low.positive!.exp));
      expect(high.positive!.stateMultiplier, closeTo(0.8, 0.001));
    });
  });

  group('过量训练：加分转损伤负荷', () {
    test('在适应范围内 → 有益超额，按 0.6 次幂递减', () {
      final d = routeOvershoot(
        plannedDose: 3,
        actualDose: 5,
        nextBand: AcwrBand.low,
        muscleRecovered: true,
        fatigued: false,
      );
      expect(d.beneficial, isTrue);
      expect(d.creditedRatio, closeTo(1 + 0.667 * 0.0 + 0.784, 0.02));
      expect(d.damageUnits, 0);
    });

    test('会把 ACWR 推入警戒区 → 不加分，转损伤', () {
      final d = routeOvershoot(
        plannedDose: 3,
        actualDose: 5,
        nextBand: AcwrBand.warning,
        muscleRecovered: true,
        fatigued: false,
      );
      expect(d.beneficial, isFalse);
      expect(d.creditedRatio, 1.0);
      expect(d.damageUnits, greaterThan(0));
      expect(d.warnings.any((w) => w.contains('就医')), isTrue);
    });

    test('疲劳状态下加练 → 直接判风险，不看 ACWR', () {
      final d = routeOvershoot(
        plannedDose: 3,
        actualDose: 4,
        nextBand: AcwrBand.low,
        muscleRecovered: true,
        fatigued: true,
      );
      expect(d.beneficial, isFalse);
      expect(d.damageUnits, greaterThan(0));
    });

    test('恢复间隔不足 48 小时 → 风险', () {
      expect(
        muscleRecovered(hoursSinceSameGroup: 30, intensityZone: '增肌区'),
        isFalse,
      );
      expect(
        muscleRecovered(hoursSinceSameGroup: 50, intensityZone: '增肌区'),
        isTrue,
      );
    });

    test('风险路径下引擎不产出正分，只产出损伤单位', () {
      final out = const ValenceEngine().evaluate(
        mk(
          code: 'extra_training',
          valence: Valence.offPlan,
          doseFraction: 1.2,
        ),
        ctxOf(band: AcwrBand.high, fatigued: true),
      );
      expect(out.positive, isNull);
      expect(out.damageUnits, greaterThan(0));
    });
  });

  group('精致加分有 40% 硬上限', () {
    test('质量拉满也只能拿到基础分的 40%', () {
      final q = QualityBreakdown({'a': 1.0, 'b': 1.0, 'c': 1.0});
      expect(qualityBonusFor(baseScore: 100, quality: q), closeTo(40, 1e-9));
    });

    test('质量中等时按比例给，但不超过上限', () {
      final q = QualityBreakdown({'a': 0.5, 'b': 0.5});
      expect(qualityBonusFor(baseScore: 100, quality: q), closeTo(40, 1e-9));
    });

    test('质量很低时给得很少，绝不会倒扣', () {
      final q = QualityBreakdown({'a': 0.05});
      final v = qualityBonusFor(baseScore: 100, quality: q);
      expect(v, closeTo(5, 1e-9));
      expect(v, greaterThanOrEqualTo(0));
    });

    test('空维度不加分', () {
      expect(qualityBonusFor(baseScore: 100, quality: const QualityBreakdown({})), 0);
    });

    test('无论怎么刷维度，加分总额恒定在上限内', () {
      final huge = QualityBreakdown({for (var i = 0; i < 50; i++) 'k$i': 1.0});
      expect(qualityBonusFor(baseScore: 80, quality: huge), closeTo(32, 1e-9));
    });
  });

  group('极简加分有上限', () {
    test('效率翻倍也只能拿基础分的 15%', () {
      expect(
        efficiencyBonusFor(baseScore: 100, ratio: 2, baselineRatio: 1),
        closeTo(15, 1e-9),
      );
    });

    test('没有基线时不给效率加分（避免第一次就发奖）', () {
      expect(
        efficiencyBonusFor(baseScore: 100, ratio: 5, baselineRatio: 0),
        0,
      );
    });

    test('效率低于基线不加分也不扣分', () {
      expect(
        efficiencyBonusFor(baseScore: 100, ratio: 0.5, baselineRatio: 1),
        0,
      );
    });
  });

  group('归因去重', () {
    test('因太累缺训，而前一晚熬夜已记录 → 抑制', () {
      final r = resolveAttribution(
        behaviorCode: 'training_absence',
        day: day.addDays(1),
        answers: const {'reason': 'tired'},
        existingRootKeys: {'sleep@${day.iso}'},
      );
      expect(r.isSuppressed, isTrue);
      expect(r.rootCauseKey, 'sleep@2025-06-01');
      expect(consequenceNote(r).contains('不重复扣分'), isTrue);
    });

    test('没有熬夜记录时，缺训自己就是根因', () {
      final r = resolveAttribution(
        behaviorCode: 'training_absence',
        day: day.addDays(1),
        answers: const {'reason': 'tired'},
        existingRootKeys: const {},
      );
      expect(r.isSuppressed, isFalse);
      expect(r.rootCauseKey, 'training_absence@2025-06-02');
    });

    test('生病导致的缺训走中断期，不归因到睡眠', () {
      final r = resolveAttribution(
        behaviorCode: 'training_absence',
        day: day,
        answers: const {'reason': 'sick'},
        existingRootKeys: {'sleep@2025-06-01'},
      );
      expect(r.isSuppressed, isFalse);
    });

    test('漏复习若归因于熬夜，同样被抑制', () {
      final r = resolveAttribution(
        behaviorCode: 'missed_review',
        day: day.addDays(1),
        answers: const {'cause': 'late_sleep'},
        existingRootKeys: {'sleep@${day.iso}'},
      );
      expect(r.isSuppressed, isTrue);
    });

    test('主因取罚得最重的那条', () {
      expect(primaryIndexOf([0.2, 1.4, 0.9]), 1);
      expect(primaryIndexOf(const []), -1);
    });
  });

  group('等级曲线与缓冲池', () {
    test('累计 100 经验到 1 级，缓冲池封顶在 35%', () {
      final s = applyExp(LevelState.zero, 100);
      expect(s.level, 1);
      final cap = levelSpan(1) * cfg.levelBufferRatio;
      expect(s.buffer, closeTo(cap < 35 ? cap : 35, 1e-9));
    });

    test('负向先扣缓冲池，不动总经验', () {
      final s1 = applyExp(LevelState.zero, 200);
      final s2 = applyExp(s1, -10);
      expect(s2.totalExp, closeTo(190, 1e-9));
      expect(s2.buffer, closeTo(s1.buffer - 10, 1e-9));
      expect(s2.level, s1.level);
    });

    test('池子空了才掉级，且必须给出解释', () {
      final s1 = applyExp(LevelState.zero, 110);
      final s2 = applyExp(s1, -80);
      expect(s2.level, lessThan(s1.level));
      final note = explainDrop(
        before: s1,
        after: s2,
        state: const StateVars(sleepDebtHours: 2),
      );
      expect(note, isNotNull);
      expect(note!.contains('回补'), isTrue);
    });

    test('等级门槛严格递增', () {
      var prev = cfg.levelThreshold(0);
      for (var n = 1; n <= 10; n++) {
        final v = cfg.levelThreshold(n);
        expect(v, greaterThan(prev));
        prev = v;
      }
    });
  });

  group('安全兜底', () {
    final gate = const SafetyGate();

    test('提到胸痛 → 暂停结算并建议就医', () {
      final a = gate.check(
        drafts: [mk(answers: const {'note': '训练后胸痛'})],
        state: StateVars.zero,
      );
      expect(a, isNotNull);
      expect(a!.blocking, isTrue);
      expect(a.advice.contains('就医'), isTrue);
      expect(a.advice.contains('不做诊断'), isTrue);
    });

    test('训练 200 分钟 + 睡眠 4 小时 → 暂停', () {
      final a = gate.check(
        drafts: [
          mk(metrics: const {'session_minutes': 200.0}),
          mk(
            code: 'sleep',
            valence: Valence.negative,
            metrics: const {'effective_hours': 4.0},
          ),
        ],
        state: StateVars.zero,
      );
      expect(a, isNotNull);
      expect(a!.code, 'extreme_load_low_sleep');
    });

    test('连续 3 天高强度 → 只提示不阻断', () {
      final a = gate.check(
        drafts: [mk()],
        state: StateVars.zero,
        consecutiveHighIntensityDays: 3,
      );
      expect(a, isNotNull);
      expect(a!.blocking, isFalse);
    });

    test('普通记录不触发兜底', () {
      expect(
        gate.check(drafts: [mk()], state: StateVars.zero),
        isNull,
      );
    });
  });

  group('正向基础分', () {
    test('未达剂量不归零：一半剂量拿约 57 分', () {
      expect(baseScoreFor(0.5), closeTo(57.4, 0.2));
    });

    test('超额部分按边际递减，不会线性放大', () {
      // 1 + (3−1)^0.6 = 1 + 1.5157
      expect(marginalDecay(3.0), closeTo(2.5157, 0.001));
      expect(marginalDecay(3.0), lessThan(3.0));
    });

    test('剂量为 0 时基础分为 0', () {
      expect(baseScoreFor(0), 0);
    });
  });
}
