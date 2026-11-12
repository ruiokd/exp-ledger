/// 记忆保持率模型。
///
/// 说明（必须随结果一起展示）：
///   本项目采用 R = e^(−t/S) 的指数保持曲线。这是对 Ebbinghaus (1885) 遗忘曲线
///   的**指数近似**，并借用间隔重复调度（Woźniak, SM-2, 1990）里"记忆强度 S"
///   的概念：S 越大，同样间隔下保持率越高。
///   它不是原始实验数据的精确拟合，个体差异巨大，属于 simplified。
library;

import 'dart:math' as math;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';

/// t 天后（或小时后，只要 S 同单位）的保持率，返回 0–1。
double retention({required double hoursSinceStudy, required double strengthDays}) {
  if (hoursSinceStudy <= 0) return 1;
  if (strengthDays <= 0) return 0;
  final days = hoursSinceStudy / 24.0;
  return math.exp(-days / strengthDays).clampRange(0, 1);
}

/// 记忆强度 S（单位：天）。
///
/// 三个可解释的因子：
///   1. 主动提取比例 —— 合上书自测/复述 vs 只看一遍。主动提取显著抬高 S。
///   2. 累积接触次数 —— 用 1 + 0.35n 的线性增长并封顶 2.2，避免"刷次数"。
///   3. 间隔性   —— 分散学习 vs 一次猛灌（由 priorExposures 隐含）。
///
/// 所有因子都是经验近似，UI 上标"简化版"。
double memoryStrengthDays({
  required double activeRecallRatio,
  required int priorExposures,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  final arr = activeRecallRatio.clampRange(0, 1);
  final activeFactor = 1 + arr * (c.memoryActiveRecallBoost - 1);
  final exposureFactor =
      (1 + 0.35 * priorExposures.clamp(0, 12)).clampRange(1.0, 2.2);
  final s = c.memoryStrengthBase * activeFactor * exposureFactor;
  return s.clampRange(0.3, 60);
}

/// 给定目标保持率，反推"还剩多少天"。
double daysUntilRetentionBelow({
  required double target,
  required double strengthDays,
}) {
  if (target <= 0 || target >= 1 || strengthDays <= 0) return 0;
  return strengthDays * math.log(1 / target);
}

/// 一次学习后的记忆账本条目。
class MemoryOutcome {
  const MemoryOutcome({
    required this.strengthDays,
    required this.retention3d,
    required this.retention7d,
    required this.retention30d,
    required this.words,
    required this.activeRecallRatio,
  });

  final double strengthDays;
  final double retention3d;
  final double retention7d;
  final double retention30d;
  final int words;
  final double activeRecallRatio;

  /// 折算出"稳固词数"——3 天后仍记得的词，作为能力值增量来源。
  double get consolidatedWords => words * retention3d;
}

/// 组合一次背单词的结果。
MemoryOutcome evaluateMemory({
  required int words,
  required double activeRecallRatio,
  required int priorExposures,
  BalanceConfig? cfg,
}) {
  final s = memoryStrengthDays(
    activeRecallRatio: activeRecallRatio,
    priorExposures: priorExposures,
    cfg: cfg,
  );
  return MemoryOutcome(
    strengthDays: s,
    retention3d: retention(hoursSinceStudy: 72, strengthDays: s),
    retention7d: retention(hoursSinceStudy: 168, strengthDays: s),
    retention30d: retention(hoursSinceStudy: 720, strengthDays: s),
    words: words < 0 ? 0 : words,
    activeRecallRatio: activeRecallRatio.clampRange(0, 1),
  );
}

/// 词汇覆盖率 → 阅读难度。
///
/// 判据参考：要"基本无障碍阅读"，需覆盖约 98% 的文本词次
/// （Hu & Nation, 2000；Nation, 2006 的常用阈值）。
/// 这是门槛判据，不是精确难度评分。
class ReadingReadiness {
  const ReadingReadiness({
    required this.coverage,
    required this.knownWords,
    required this.textVocabulary,
    required this.verdict,
  });

  final double coverage;
  final int knownWords;
  final int textVocabulary;

  /// 'comfortable' | 'workable' | 'strained'
  final String verdict;

  String get verdictLabel => switch (verdict) {
        'comfortable' => '可以直接读',
        'workable' => '能读，但会卡',
        _ => '现在读会很累',
      };
}

ReadingReadiness readingReadiness({
  required int knownWords,
  required int textVocabulary,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  final coverage = textVocabulary <= 0 ? 0.0 : knownWords / textVocabulary;
  final v = coverage >= c.memoryCoverageThreshold
      ? 'comfortable'
      : (coverage >= c.memoryCoverageThreshold - 0.04 ? 'workable' : 'strained');
  return ReadingReadiness(
    coverage: coverage.clampRange(0, 1),
    knownWords: knownWords,
    textVocabulary: textVocabulary,
    verdict: v,
  );
}
