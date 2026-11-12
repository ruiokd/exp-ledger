import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/sleep_metrics.dart';

/// 判为熬夜的最小越界分钟数。低于这个值只提示不判负——
/// 15 分钟以内更像是测量误差，不值得为它扣分。
const int _lateToleranceMinutes = 15;

/// 判为睡眠不足的最小缺口（小时）。
const double _gapToleranceHours = 1.0;

/// 目标剂量：睡够个人需求。
const double _targetSleepDose = 1.0;

/// 睡眠。一次录入，可能得出正向（睡够了）或负向（熬夜/欠睡）。
///
/// 之所以做成一个行为而不是两个，是因为用户晚上只睡一次觉：
/// 拆成"熬夜"和"睡眠达标"两个入口，会让同一次睡眠被记录两遍。
final BehaviorDef sleepBehavior = BehaviorDef(
  code: 'sleep',
  name: '睡眠',
  category: BehaviorCategory.positive,
  valence: Valence.neutral,
  axis: ProjectAxis.discipline,
  iconName: 'moon',
  aliases: const [
    '睡眠', '睡觉', '睡了', '入睡', '熬夜', '失眠', '早睡', '补觉',
    '两点才睡', '睡得晚', '睡眠不足',
  ],
  keywords: const ['00:', '01:', '02:', '03:', '醒', '睡', '半夜', '躺下'],
  standardDefinition:
      '1 次睡眠 = 一次连续的夜间睡眠，从入睡时刻算到起床时刻。'
      '有效睡眠 = 在床时长 − 中途清醒时长。'
      '熬夜 = 入睡时间晚于你的个人界线（默认 00:20）。',
  misconception: '睡够 8 小时但凌晨 4 点睡，和 23 点睡 8 小时并不等价——作息稳定性本身就是一个变量。',
  targetDose: _targetSleepDose,
  doseUnit: '晚',
  defaultConfidence: Confidence.selfReport,
  needsPlanGate: false,
  slotScope: SlotScope.perDay,
  resolveValence: (d) {
    final late = d.metrics['late_minutes'] ?? 0;
    final gap = d.metrics['gap_hours'] ?? 0;
    if (late > _lateToleranceMinutes || gap >= _gapToleranceHours) {
      return Valence.negative;
    }
    return Valence.positive;
  },
  questions: [
    QuestionSpec(
      id: 'bed',
      title: '几点睡着的？',
      why: '入睡时刻决定有没有越过你的界线。',
      kind: QuestionKind.timeOfDay,
      inheritFromLast: true,
      numberSpec: const NumberSpec(
        min: 0,
        max: 1439,
        initial: 1400,
        step: 5,
        unit: '',
      ),
    ),
    QuestionSpec(
      id: 'wake',
      title: '几点醒的？',
      why: '和入睡一起算出在床时长。',
      kind: QuestionKind.timeOfDay,
      inheritFromLast: true,
      numberSpec: const NumberSpec(
        min: 0,
        max: 1439,
        initial: 430,
        step: 5,
        unit: '',
      ),
    ),
    QuestionSpec(
      id: 'wakeups',
      title: '半夜醒了几次？',
      why: '醒了但没睡着的时间不算有效睡眠。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('0', '一觉到天亮'),
        QuestionOption('1', '1 次'),
        QuestionOption('2', '2 次'),
        QuestionOption('3', '3 次及以上'),
      ],
    ),
    QuestionSpec(
      id: 'quality',
      title: '睡得怎么样？',
      why: '主观质量不影响时长计算，但会影响第二天的状态评估。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('good', '挺沉'),
        QuestionOption('ok', '一般'),
        QuestionOption('bad', '很浅，像没睡'),
        QuestionOption(kUnknownValue, '说不好'),
      ],
    ),
  ],
  derive: (ctx) {
    final bedText = ctx.strOr('bed', '23:00');
    final wakeText = ctx.strOr('wake', '07:00');
    final bed = MinuteOfDay.parse(bedText);
    final wake = MinuteOfDay.parse(wakeText);
    final wakeups = ctx.intOr('wakeups', 0);
    final quality = ctx.strOr('quality', 'ok');

    // 每次醒来的默认时长：1 次按 12 分钟、2 次按 10、3 次以上按 8。
    final avgAwake = switch (wakeups) { 0 => 0.0, 1 => 12.0, 2 => 10.0, _ => 8.0 };

    final outcome = evaluateSleep(
      bed: bed,
      wake: wake,
      awakenings: wakeups,
      avgAwakeMinutes: avgAwake,
      profile: ctx.profile,
    );

    final line = ctx.profile.sleepLine;
    final isLate = outcome.lateMinutes > 0;

    final interpretation = isLate
        ? '入睡 ${bed.label}，比你的界线晚 ${humanizeMinutes(outcome.lateMinutes)}'
        : '入睡 ${bed.label}，没有越过你的界线';

    final lines = <ReceiptLine>[
      ReceiptLine('系统理解', '${bed.label} 入睡 → ${wake.label} 醒来'),
      ReceiptLine(
        '有效睡眠',
        '${outcome.durationLabel}（在床 ${humanizeHours(outcome.windowHours)}）',
      ),
      ReceiptLine('睡眠效率', '${(outcome.efficiency * 100).round()}%'),
      if (isLate)
        ReceiptLine(
          '熬夜判定',
          '比界线 ${line.label} 晚 ${humanizeMinutes(outcome.lateMinutes)}',
          emphasis: true,
        )
      else
        ReceiptLine('熬夜判定', '没有越界（界线 ${line.label}）'),
      if (outcome.gapHours > 0)
        ReceiptLine(
          '睡眠缺口',
          '比需要的 ${humanizeHours(ctx.profile.sleepNeedHours)} 少 ${humanizeHours(outcome.gapHours)}',
          emphasis: true,
        )
      else
        ReceiptLine('睡眠缺口', '已满足 ${humanizeHours(ctx.profile.sleepNeedHours)}'),
    ];

    final notes = <String>[];
    if (outcome.efficiency < 0.85) {
      notes.add('睡眠效率 ${(outcome.efficiency * 100).round()}%，低于常用的 85% 参考线。');
    }
    if (wakeups >= 3) {
      notes.add('夜醒 3 次以上，有效睡眠按每次 8 分钟扣减，这是估算不是测量。');
    }
    if (quality == 'bad') {
      notes.add('主观质量差已记录，它不会额外扣分。');
    }

    final gapDose = outcome.gapHours;
    final dose = (outcome.effectiveHours / ctx.profile.sleepNeedHours)
        .clampRange(0, 1.2);

    return DerivedResult(
      slotKey: 'night',
      interpretation: interpretation,
      lines: lines,
      metrics: {
        'bed_minutes': bed.minutes.toDouble(),
        'wake_minutes': wake.minutes.toDouble(),
        'window_hours': outcome.windowHours,
        'effective_hours': outcome.effectiveHours,
        'efficiency': outcome.efficiency,
        'late_minutes': outcome.lateMinutes.toDouble(),
        'gap_hours': gapDose,
        'wakeups': wakeups.toDouble(),
        'sleep_need_hours': ctx.profile.sleepNeedHours,
        'exp_sign': isLate || gapDose >= _gapToleranceHours ? -1 : 1,
      },
      normalized: {
        ...ctx.answers,
        'bed': bed.label,
        'wake': wake.label,
        'wakeups': wakeups,
        'quality': quality,
      },
      confidence: ctx.resolveConfidence(
        ctx.profile.sleepConfidence == Confidence.calibrated
            ? Confidence.formula
            : Confidence.selfReport,
      ),
      doseFraction: dose,
      notes: notes,
    );
  },
);
