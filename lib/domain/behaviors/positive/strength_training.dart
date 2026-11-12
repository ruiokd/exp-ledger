import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/energy.dart';
import 'package:exp_ledger/domain/science/training_dose.dart';

/// 动作表：MET 取值参考 Ainsworth MET Compendium (2011) 的抗阻训练条目，
/// 复合动作（深蹲/硬拉）取 6.0，孤立动作取 5.0。这是量级近似，不是精确能耗。
class _Exercise {
  const _Exercise(this.code, this.label, this.met, this.isCompound);

  final String code;
  final String label;
  final double met;
  final bool isCompound;
}

const List<_Exercise> _exercises = [
  _Exercise('squat', '深蹲', 6.0, true),
  _Exercise('deadlift', '硬拉', 6.0, true),
  _Exercise('bench', '卧推', 5.0, true),
  _Exercise('row', '划船', 5.0, true),
  _Exercise('pullup', '引体向上', 5.5, false),
  _Exercise('ohp', '肩推', 5.0, false),
  _Exercise('lunge', '弓步蹲', 5.5, false),
  _Exercise('accessory', '其他孤立动作', 4.0, false),
];

_Exercise _exerciseOf(String code) => _exercises.firstWhere(
      (e) => e.code == code,
      orElse: () => _exercises.first,
    );

/// 目标剂量：3 个"充分强度"的有效组，是增肌的最低有效刺激的常见参考量级。
const double _targetEffectiveSets = 3.0;

/// 抗阻训练（含深蹲、硬拉、卧推等）。
final BehaviorDef strengthTrainingBehavior = BehaviorDef(
  code: 'strength_training',
  name: '抗阻训练',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.strength,
  iconName: 'dumbbell',
  aliases: const [
    '深蹲', '硬拉', '卧推', '划船', '引体向上', '肩推', '弓步蹲',
    '撸铁', '练腿', '练胸', '练背', '力量训练', '举铁', '健身',
    'squat', 'deadlift', 'bench',
  ],
  keywords: const ['组', '次数', '重量', 'kg', 'RM', 'RIR', '力竭', '组间'],
  standardDefinition:
      '1 组 = 连续完成该动作规定次数后停下休息；'
      '1 次 = 完整完成向心+离心且姿态未崩的一次重复。'
      '只有"接近力竭但仍保持动作标准"的组才计入有效组。',
  misconception: '很多人把"总共做了多少组"当训练量，其实强度（离力竭多远）比组数更影响刺激。',
  targetDose: _targetEffectiveSets,
  doseUnit: '有效组',
  defaultConfidence: Confidence.selfReport,
  needsPlanGate: true,
  slotScope: SlotScope.perSlot,
  questions: [
    QuestionSpec(
      id: 'exercise',
      title: '做的哪个动作？',
      why: '不同动作的能耗与刺激不一样，先定动作再问量。',
      kind: QuestionKind.choice,
      options: [
        for (final e in _exercises)
          QuestionOption(e.code, e.label,
              sublabel: e.isCompound ? '复合动作' : '单关节'),
      ],
    ),
    QuestionSpec(
      id: 'load_type',
      title: '负重方式',
      why: '负重形式决定我们怎么估容量。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('barbell', '杠铃'),
        QuestionOption('dumbbell', '哑铃'),
        QuestionOption('machine', '器械'),
        QuestionOption('kettlebell', '壶铃'),
        QuestionOption('bodyweight', '自重'),
      ],
    ),
    QuestionSpec(
      id: 'weight',
      title: '用了多重？',
      why: '重量是估算容量和强度的关键。',
      kind: QuestionKind.number,
      inheritFromLast: true,
      rangeHint: '常规 20–120 kg',
      assist: '不确定就选最接近的档位，之后可以改。',
      showIf: (a) => a.strOf('load_type') != 'bodyweight',
      numberSpec: const NumberSpec(
        min: 0,
        max: 300,
        initial: 60,
        step: 2.5,
        unit: ' kg',
        decimals: 1,
        presets: [20, 40, 60, 80, 100],
      ),
    ),
    QuestionSpec(
      id: 'reps',
      title: '每组做了几次？',
      why: '次数决定这一组偏向力量还是耐力。',
      kind: QuestionKind.number,
      inheritFromLast: true,
      rangeHint: '常规 8–15 次',
      numberSpec: const NumberSpec(
        min: 1,
        max: 50,
        initial: 12,
        step: 1,
        unit: ' 次',
        presets: [5, 8, 10, 12, 15, 20],
      ),
    ),
    QuestionSpec(
      id: 'sets',
      title: '一共几组？',
      why: '组数是训练量的底盘。',
      kind: QuestionKind.number,
      inheritFromLast: true,
      rangeHint: '常规 3–5 组',
      numberSpec: const NumberSpec(
        min: 1,
        max: 15,
        initial: 3,
        step: 1,
        unit: ' 组',
        presets: [1, 2, 3, 4, 5],
      ),
    ),
    QuestionSpec(
      id: 'rir',
      title: '最后一组还剩几次余力？',
      why: '离力竭越近，同等组数的刺激越强，但恢复成本也越高。',
      kind: QuestionKind.choice,
      rangeHint: '大部分增肌训练落在 1–3 次余力',
      options: const [
        QuestionOption('5', '还有 5 次以上', sublabel: '很轻松'),
        QuestionOption('4', '还有 3–4 次', sublabel: '中等'),
        QuestionOption('2', '还有 1–2 次', sublabel: '接近力竭'),
        QuestionOption('0', '一次都做不动了', sublabel: '力竭'),
        QuestionOption(kUnknownValue, '说不好', sublabel: '按"中等"估'),
      ],
    ),
    QuestionSpec(
      id: 'compensation',
      title: '动作有变形吗？',
      why: '代偿意味着名义次数没全落在目标肌肉上。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('none', '没有，很稳'),
        QuestionOption('mild', '有点塌腰/借力'),
        QuestionOption('severe', '明显变形，中途停了'),
      ],
    ),
  ],
  derive: (ctx) {
    final weight = ctx.numOr('weight', 0);
    final reps = ctx.intOr('reps', 0);
    final sets = ctx.intOr('sets', 0);
    final rir = ctx.intOr('rir', 4);
    final compCode = ctx.strOr('compensation', 'none');
    final ex = _exerciseOf(ctx.strOr('exercise', 'squat'));

    final intensity = intensityFactorFromRir(rir, ctx.config);
    final comp = compensationFactor(compCode);
    final effSets = effectiveSets(
      sets: sets,
      reps: reps,
      intensityFactor: intensity,
      compensation: comp,
      cfg: ctx.config,
    );
    final minutes = estimateSessionMinutes(sets: sets, reps: reps, cfg: ctx.config);
    final kcal = metKcal(met: ex.met, weightKg: ctx.profile.weightKg, minutes: minutes);
    final vol = volumeLoad(sets: sets, reps: reps, weightKg: weight);
    final oneRm = ctx.profile.oneRmSquatKg;
    final rel = relativeIntensity(weight: weight, oneRm: oneRm);

    final weightPhrase =
        weight <= 0 ? '自重' : '@ ${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1)}kg';
    final interpretation =
        '$sets 组${ex.label} ≈ $reps 次 $weightPhrase';

    final lines = <ReceiptLine>[
      ReceiptLine('动作', ex.label),
      ReceiptLine('系统理解', '$sets 组 × $reps 次 $weightPhrase'),
      ReceiptLine(
        '估算消耗',
        '约 ${kcal.roundTo(0).toStringAsFixed(0)} kcal（含组间休息，简化估算）',
      ),
      ReceiptLine(
        '有效训练',
        '有效组 +${effSets.toStringAsFixed(1)} · 强度系数 ${intensity.toStringAsFixed(1)}',
        emphasis: true,
      ),
      if (vol > 0) ReceiptLine('总容量', '${vol.roundTo(0).toStringAsFixed(0)} kg'),
      if (rel != null) ReceiptLine('相对强度', '约 ${(rel * 100).round()}% 1RM · ${trainingZoneLabel(rel)}'),
    ];

    final notes = <String>[];
    final warnings = <String>[];
    if (compCode == 'severe') {
      notes.add('动作变形的那部分已按 65% 折算，这是保守处理，不是惩罚。');
    }
    if (rir <= 0 && sets >= 5) {
      warnings.add('多组力竭叠加，48 小时内同一肌群建议不再安排大负荷。');
    }
    if (ctx.isUnknown('rir')) {
      notes.add('余力按"中等"估算，实际强度可能更高或更低。');
    }

    final dose = (effSets / _targetEffectiveSets).clampRange(0, 1.5);
    return DerivedResult(
      slotKey: ex.code,
      interpretation: interpretation,
      lines: lines,
      metrics: {
        'sets': sets.toDouble(),
        'reps': reps.toDouble(),
        'weight_kg': weight,
        'volume_load': vol,
        'effective_sets': effSets,
        'intensity_factor': intensity,
        'session_minutes': minutes,
        'kcal': kcal,
        'met': ex.met,
        'rir': rir.toDouble(),
        'compensation_factor': comp,
        'exp_sign': 1,
      },
      normalized: {
        ...ctx.answers,
        'exercise': ex.code,
        'reps': reps,
        'sets': sets,
        'weight': weight,
        'rir': rir,
        'compensation': compCode,
      },
      confidence: ctx.resolveConfidence(
        rel != null ? Confidence.formula : Confidence.selfReport,
      ),
      doseFraction: dose,
      notes: notes,
      warnings: warnings,
    );
  },
);
