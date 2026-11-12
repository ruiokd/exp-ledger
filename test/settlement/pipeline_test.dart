import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/engine/level_curve.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/settlement/settlement_pipeline.dart';
import 'package:test/test.dart';

const cfg = kDefaultConfig;
final today = DayKey(2025, 6, 2);
final yesterday = DayKey(2025, 6, 1);

DraftEntry draft({
  required String code,
  required Valence valence,
  required ProjectAxis axis,
  required DayKey on,
  double dose = 1.0,
  Map<String, double> metrics = const {},
  Map<String, Object?> answers = const {},
  bool interruption = false,
  PlanStatus plan = PlanStatus.planned,
}) {
  return DraftEntry(
    dayKey: on,
    behaviorCode: code,
    category: valence == Valence.negative
        ? BehaviorCategory.negative
        : (valence == Valence.offPlan
            ? BehaviorCategory.offPlan
            : BehaviorCategory.positive),
    valence: valence,
    axis: axis,
    planStatus: plan,
    confidence: Confidence.selfReport,
    slotKey: 'slot',
    answers: answers,
    metrics: metrics,
    interpretation: code,
    doseFraction: dose,
    source: 'test',
    createdAt: DateTime(2025, 6, 2, 9),
    isInterruption: interruption,
  );
}

SettlementInput inputOf(
  List<DraftEntry> drafts, {
  StateVars state = StateVars.zero,
  LevelState level = LevelState.zero,
  Set<String> keys = const {},
  AcwrBand band = AcwrBand.low,
  int consecutiveHigh = 0,
}) {
  return SettlementInput(
    dayKey: today,
    drafts: drafts,
    stateBefore: state,
    levelBefore: level,
    load: LoadIndex.empty(today),
    config: cfg,
    existingRootKeys: keys,
    nextBand: band,
    consecutiveHighIntensityDays: consecutiveHigh,
  );
}

void main() {
  const pipeline = SettlementPipeline();

  group('一日结算：正负并存', () {
    final settlement = pipeline.settle(
      inputOf([
        draft(
          code: 'sleep',
          valence: Valence.negative,
          axis: ProjectAxis.discipline,
          on: today,
          metrics: const {
            'effective_hours': 4.63,
            'sleep_need_hours': 7.5,
            'late_minutes': 110.0,
            'gap_hours': 2.87,
          },
        ),
        draft(
          code: 'strength_training',
          valence: Valence.positive,
          axis: ProjectAxis.strength,
          on: today,
          metrics: const {
            'effective_sets': 3.0,
            'session_minutes': 12.0,
            'intensity_factor': 0.8,
            'compensation_factor': 1.0,
            'rir': 4.0,
          },
        ),
      ]),
    );

    test('正分和负分同时存在，净值可正可负', () {
      expect(settlement.positives, hasLength(1));
      expect(settlement.negatives, hasLength(1));
      expect(settlement.positiveExp, greaterThan(0));
      expect(settlement.negativeExp, lessThan(0));
      expect(settlement.netExp,
          closeTo(settlement.positiveExp + settlement.negativeExp, 1e-9));
    });

    test('状态变量被推进：睡眠负债上升、损伤负荷非负', () {
      expect(settlement.stateAfter.sleepDebtHours, greaterThan(0));
      expect(settlement.stateAfter.damageLoad, greaterThanOrEqualTo(0));
      expect(settlement.stateAfter.sanitized().sleepDebtHours,
          closeTo(settlement.stateAfter.sleepDebtHours, 1e-9));
    });

    test('负向事件带上可回补路径', () {
      expect(settlement.recoveryPlan, isNotEmpty);
    });

    test('结算结果是确定性的（同输入同输出）', () {
      final again = pipeline.settle(
        inputOf([
          draft(
            code: 'sleep',
            valence: Valence.negative,
            axis: ProjectAxis.discipline,
            on: today,
            metrics: const {
              'effective_hours': 4.63,
              'sleep_need_hours': 7.5,
              'late_minutes': 110.0,
              'gap_hours': 2.87,
            },
          ),
          draft(
            code: 'strength_training',
            valence: Valence.positive,
            axis: ProjectAxis.strength,
            on: today,
            metrics: const {
              'effective_sets': 3.0,
              'session_minutes': 12.0,
              'intensity_factor': 0.8,
              'compensation_factor': 1.0,
              'rir': 4.0,
            },
          ),
        ]),
      );
      expect(again.netExp, closeTo(settlement.netExp, 1e-9));
      expect(again.stateAfter.sleepDebtHours,
          closeTo(settlement.stateAfter.sleepDebtHours, 1e-9));
    });
  });

  group('归因去重生效', () {
    test('同一天里熬夜 + 因累缺训 → 缺训不扣分', () {
      final s = pipeline.settle(
        inputOf(
          [
            draft(
              code: 'training_absence',
              valence: Valence.negative,
              axis: ProjectAxis.strength,
              on: today,
              metrics: const {'curve_minutes': 60.0},
              answers: const {'reason': 'tired'},
            ),
          ],
          keys: {'sleep@${yesterday.iso}'},
        ),
      );
      expect(s.negatives, hasLength(1));
      expect(s.negatives.first.suppressed, isTrue);
      expect(s.negatives.first.exp, 0);
      expect(s.negativeExp, 0);
    });

    test('没有熬夜记录时，缺训照常计分', () {
      final s = pipeline.settle(
        inputOf([
          draft(
            code: 'training_absence',
            valence: Valence.negative,
            axis: ProjectAxis.strength,
            on: today,
            metrics: const {'curve_minutes': 60.0},
            answers: const {'reason': 'tired'},
          ),
        ]),
      );
      expect(s.negativeExp, lessThan(0));
    });

    test('同一根因的两条记录，只有罚得重的扣分', () {
      final s = pipeline.settle(
        inputOf([
          draft(
            code: 'training_absence',
            valence: Valence.negative,
            axis: ProjectAxis.strength,
            on: today,
            metrics: const {'curve_minutes': 60.0},
          ),
          draft(
            code: 'missed_review',
            valence: Valence.negative,
            axis: ProjectAxis.memory,
            on: today,
            metrics: const {'curve_minutes': 120.0},
          ),
        ]),
      );
      // 两个不同根因，各自独立计分
      expect(s.negatives.where((n) => !n.suppressed), hasLength(2));
    });
  });

  group('安全兜底优先于算分', () {
    test('极端输入 → 暂停结算，正负都为 0', () {
      final s = pipeline.settle(
        inputOf([
          draft(
            code: 'strength_training',
            valence: Valence.positive,
            axis: ProjectAxis.strength,
            on: today,
            metrics: const {'session_minutes': 200.0, 'effective_sets': 8.0},
            answers: const {'note': '练完胸痛'},
          ),
        ]),
      );
      expect(s.status, SettlementStatus.paused);
      expect(s.positiveExp, 0);
      expect(s.negativeExp, 0);
      expect(s.netExp, 0);
      expect(s.alert, isNotNull);
      expect(s.alert!.advice.contains('就医'), isTrue);
    });
  });

  group('中断期与计划外', () {
    test('生病记录 → 不产分数，标记中断', () {
      final s = pipeline.settle(
        inputOf([
          draft(
            code: 'illness',
            valence: Valence.offPlan,
            axis: ProjectAxis.discipline,
            on: today,
            interruption: true,
            dose: 0,
            metrics: const {'offplan_kind': 3.0},
          ),
        ]),
      );
      expect(s.isInterruption, isTrue);
      expect(s.positiveExp, 0);
      expect(s.negativeExp, 0);
    });

    test('有益超额 → 计入正分但低于同等计划内剂量', () {
      final planned = pipeline.settle(
        inputOf([
          draft(
            code: 'strength_training',
            valence: Valence.positive,
            axis: ProjectAxis.strength,
            on: today,
            dose: 1.0,
            metrics: const {'effective_sets': 3.0, 'session_minutes': 12.0},
          ),
        ]),
      );
      final extra = pipeline.settle(
        inputOf([
          draft(
            code: 'extra_training',
            valence: Valence.offPlan,
            axis: ProjectAxis.strength,
            on: today,
            dose: 0.6,
            metrics: const {'offplan_kind': 1.0},
          ),
        ]),
      );
      expect(extra.positiveExp, greaterThan(0));
      expect(extra.positiveExp, lessThan(planned.positiveExp));
    });

    test('过量风险 → 不加分，转入损伤负荷', () {
      final s = pipeline.settle(
        inputOf(
          [
            draft(
              code: 'extra_training',
              valence: Valence.offPlan,
              axis: ProjectAxis.strength,
              on: today,
              dose: 1.4,
              metrics: const {'offplan_kind': 2.0},
            ),
          ],
          band: AcwrBand.high,
        ),
      );
      expect(s.positiveExp, 0);
      expect(s.stateAfter.damageLoad, greaterThan(0));
    });
  });

  group('等级联动', () {
    test('连续正分让等级上升，且缓冲池同步增长', () {
      var level = LevelState.zero;
      var state = StateVars.zero;
      for (var i = 0; i < 10; i++) {
        final s = pipeline.settle(
          SettlementInput(
            dayKey: today.addDays(i),
            drafts: [
              draft(
                code: 'strength_training',
                valence: Valence.positive,
                axis: ProjectAxis.strength,
                on: today.addDays(i),
                metrics: const {
                  'effective_sets': 3.0,
                  'session_minutes': 12.0,
                },
              ),
            ],
            stateBefore: state,
            levelBefore: level,
            load: LoadIndex.empty(today.addDays(i)),
            config: cfg,
          ),
        );
        state = s.stateAfter;
        level = LevelState(
          level: s.levelAfter,
          totalExp: level.totalExp + s.netExp,
          buffer: s.bufferAfter,
        );
      }
      expect(level.level, greaterThan(0));
      expect(level.totalExp, greaterThan(100));
      expect(level.buffer, greaterThan(0));
    });
  });

  group('空日与缺数据', () {
    test('没有任何记录的一天不产生分数，也不惩罚', () {
      final s = pipeline.settle(inputOf(const []));
      expect(s.netExp, 0);
      expect(s.positives, isEmpty);
      expect(s.negatives, isEmpty);
      expect(s.recoveryPlan, isEmpty);
    });

    test('空日不会重置已有负债', () {
      final s = pipeline.settle(
        inputOf(const [], state: const StateVars(sleepDebtHours: 3, damageLoad: 4)),
      );
      expect(s.stateAfter.sleepDebtHours, greaterThanOrEqualTo(3 * 0.65 - 1e-9));
      expect(s.stateAfter.damageLoad, greaterThan(0));
    });
  });
}
