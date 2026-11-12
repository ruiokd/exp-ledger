import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/forgetting_curve.dart';

/// 目标剂量：20 词，是"一次有效学习单元"的常见量级。
const double _targetWords = 20.0;

/// 主动提取比例的估法（问卷 → 数值）。这是启发式映射，不是心理学量表。
double _activeRecallRatio(String method) => switch (method) {
      'active' => 0.85,
      'mixed' => 0.50,
      'passive' => 0.20,
      _ => 0.50,
    };

final BehaviorDef vocabularyReviewBehavior = BehaviorDef(
  code: 'vocabulary_review',
  name: '背单词',
  category: BehaviorCategory.positive,
  valence: Valence.positive,
  axis: ProjectAxis.memory,
  iconName: 'book',
  aliases: const [
    '背单词', '背词', '单词', '刷词', '复习单词', '词汇', '记单词',
    'vocabulary', 'anki', 'vocab',
  ],
  keywords: const ['词', '英语', '新词', '复习', '默写', '复述', '提取'],
  standardDefinition:
      '1 个词 = 完成一轮"看词 → 回忆词义"的提取动作；'
      '只看不回忆不算有效接触。'
      '1 次有效学习 = 至少 10 个词、其中一半以上是主动回忆。',
  misconception: '通读一遍词表带来的熟悉感会骗人：认得出 ≠ 想得起，主动提取才算有效。',
  targetDose: _targetWords,
  doseUnit: '词',
  defaultConfidence: Confidence.selfReport,
  needsPlanGate: false,
  questions: [
    QuestionSpec(
      id: 'mode',
      title: '这批词是什么？',
      why: '新词和复习的保持曲线完全不同。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('new', '全新的一批'),
        QuestionOption('review', '之前学过的复习'),
        QuestionOption('mixed', '新的 + 复习混着'),
      ],
    ),
    QuestionSpec(
      id: 'words',
      title: '一共多少个词？',
      why: '词数决定这一次的剂量。',
      kind: QuestionKind.number,
      inheritFromLast: true,
      rangeHint: '常规 10–30 个',
      numberSpec: const NumberSpec(
        min: 1,
        max: 500,
        initial: 20,
        step: 5,
        unit: ' 个',
        presets: [10, 20, 30, 50],
      ),
    ),
    QuestionSpec(
      id: 'method',
      title: '怎么过的这一遍？',
      why: '这是决定保持率的最大变量。',
      kind: QuestionKind.choice,
      rangeHint: '主动回忆的效果通常明显好于反复看',
      options: const [
        QuestionOption('active', '合上书自己回想', sublabel: '复述/自测'),
        QuestionOption('mixed', '一半回忆一半看'),
        QuestionOption('passive', '只是看了一遍', sublabel: '没自测'),
        QuestionOption(kUnknownValue, '记不清了'),
      ],
    ),
    QuestionSpec(
      id: 'exposures',
      title: '这批词你见过几次了？',
      why: '接触次数越多，遗忘越慢。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('1', '第一次见'),
        QuestionOption('2', '第 2 次'),
        QuestionOption('3', '第 3 次'),
        QuestionOption('4', '4 次以上'),
      ],
    ),
    QuestionSpec(
      id: 'tested',
      title: '当场自测了吗？',
      why: '当场能回想起来，是记忆真的落地的信号。',
      kind: QuestionKind.choice,
      options: const [
        QuestionOption('yes', '测了，大部分能想起来'),
        QuestionOption('partial', '测了，只对上一半'),
        QuestionOption('no', '没测'),
      ],
    ),
  ],
  derive: (ctx) {
    final words = ctx.intOr('words', 0);
    final method = ctx.strOr('method', 'mixed');
    final exposures = ctx.intOr('exposures', 1);
    final mode = ctx.strOr('mode', 'new');
    final tested = ctx.strOr('tested', 'no');

    var arr = _activeRecallRatio(method);
    if (tested == 'partial') arr = (arr * 0.8).clampRange(0, 1);
    if (tested == 'no') arr = (arr * 0.7).clampRange(0, 1);

    final outcome = evaluateMemory(
      words: words,
      activeRecallRatio: arr,
      priorExposures: exposures,
      cfg: ctx.config,
    );

    final p3 = (outcome.retention3d * 100).round();
    final kept3 = outcome.consolidatedWords.round();
    final interpretation =
        '$words 个词，3 天后预计还记得 $kept3 个（约 $p3%）';

    final lines = <ReceiptLine>[
      ReceiptLine('批次', switch (mode) {
        'new' => '全新 $words 个',
        'review' => '复习 $words 个',
        _ => '新+复习共 $words 个',
      }),
      ReceiptLine('主动提取比例', '${(arr * 100).round()}%'),
      ReceiptLine('记忆强度 S', '${outcome.strengthDays.toStringAsFixed(1)} 天'),
      ReceiptLine('3 天后保持率', '约 $p3%（简化版遗忘曲线）'),
      ReceiptLine('7 天后保持率', '约 ${(outcome.retention7d * 100).round()}%'),
      ReceiptLine('稳固词数', '+${kept3} 个', emphasis: true),
    ];

    final notes = <String>[];
    if (mode == 'new' && arr < 0.5) {
      notes.add('纯看一遍的记忆强度约为主动回忆的 1/3，下次试试合上书复述。');
    }
    if (exposures >= 3) {
      notes.add('已经见过 3 次以上，这次主要是在把 S 拉长，属于该做的事。');
    }
    if (ctx.isUnknown('method')) {
      notes.add('方式按"一半回忆一半看"估算，保持率可能被高估或低估。');
    }

    final dose = (outcome.consolidatedWords / _targetWords).clampRange(0, 1.5);
    return DerivedResult(
      slotKey: mode,
      interpretation: interpretation,
      lines: lines,
      metrics: {
        'words': words.toDouble(),
        'active_recall_ratio': arr,
        'strength_days': outcome.strengthDays,
        'retention_3d': outcome.retention3d,
        'retention_7d': outcome.retention7d,
        'retention_30d': outcome.retention30d,
        'consolidated_words': outcome.consolidatedWords,
        'exposures': exposures.toDouble(),
        'exp_sign': 1,
      },
      normalized: {
        ...ctx.answers,
        'words': words,
        'method': method,
        'exposures': exposures,
        'tested': tested,
      },
      confidence: ctx.resolveConfidence(Confidence.selfReport),
      doseFraction: dose,
      notes: notes,
    );
  },
);
