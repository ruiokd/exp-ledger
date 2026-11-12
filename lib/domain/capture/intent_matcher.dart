import 'dart:math' as math;

import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';

/// 一次意图匹配的结果。
class MatchResult {
  const MatchResult({
    required this.behavior,
    required this.score,
    required this.hits,
    this.prefill = const {},
  });

  final BehaviorDef behavior;

  /// 0–1，用于排序与"是否展示"的判断，不代表概率。
  final double score;

  /// 命中的词条，用来在卡片上解释"为什么觉得你在说这个"。
  final List<String> hits;

  /// 命中词条能预填的答案（如"深蹲"→ exercise=squat），少问一题。
  final Map<String, String> prefill;

  bool get isConfident => score >= IntentMatcher.showThreshold;
}

/// 人话 → 行为库条目。
///
/// 设计取向：宁可多给一张候选卡，也不要把用户推进自由记录。
/// 所以阈值偏低（0.34），但排序必须准。
class IntentMatcher {
  IntentMatcher(this.library);

  final BehaviorLibrary library;

  /// 低于这个分数就不展示候选卡，直接走自由记录。
  static const double showThreshold = 0.34;

  /// 命中词条能预填的答案：只覆盖最常见的那几个说法。
  static const Map<String, Map<String, Map<String, String>>> _prefills = {
    'strength_training': {
      '深蹲': {'exercise': 'squat'},
      '硬拉': {'exercise': 'deadlift'},
      '卧推': {'exercise': 'bench'},
      '划船': {'exercise': 'row'},
      '引体': {'exercise': 'pullup'},
      '肩推': {'exercise': 'ohp'},
      '弓步': {'exercise': 'lunge'},
      '练腿': {'exercise': 'squat'},
      '练胸': {'exercise': 'bench'},
      '练背': {'exercise': 'row'},
    },
    'cardio': {
      '跑步': {'type': 'run'},
      '跑了': {'type': 'run'},
      '慢跑': {'type': 'run'},
      '骑行': {'type': 'cycle'},
      '骑车': {'type': 'cycle'},
      '游泳': {'type': 'swim'},
      '快走': {'type': 'walk'},
      '跳绳': {'type': 'rope'},
      '打球': {'type': 'ball'},
    },
    'vocabulary_review': {
      '背单词': {'mode': 'new'},
      '复习单词': {'mode': 'review'},
    },
    'sleep': {
      '熬夜': {'bed': '02:00'},
      '两点才睡': {'bed': '02:00'},
    },
  };

  /// 归一化：去掉空白与标点，统一小写。中文不受影响，英文大小写不敏感。
  static String normalize(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final isCjk = rune >= 0x4E00 && rune <= 0x9FFF;
      final isAlnum = RegExp(r'[a-z0-9]').hasMatch(ch);
      if (isCjk || isAlnum) buf.write(ch);
    }
    return buf.toString();
  }

  /// 主入口。返回按分数降序的候选（最多 [limit] 个）。
  List<MatchResult> match(String input, {int limit = 3}) {
    final q = normalize(input);
    if (q.isEmpty) return const [];

    final results = <MatchResult>[];
    for (final behavior in library.captureable) {
      final scored = _score(behavior, q);
      if (scored.score > 0) results.add(scored);
    }
    results.sort((a, b) => b.score.compareTo(a.score));

    // 同分时按"更具体的词条长度"排，避免泛化条目压过精确条目。
    final filtered =
        results.where((r) => r.score >= showThreshold).take(limit).toList();
    return filtered;
  }

  MatchResult best(String input) {
    final m = match(input, limit: 1);
    return m.isEmpty
        ? MatchResult(
            behavior: library.require('strength_training'),
            score: 0,
            hits: const [],
          )
        : m.first;
  }

  MatchResult _score(BehaviorDef behavior, String q) {
    var raw = 0.0;
    final hits = <String>[];
    var bestTerm = '';
    var bestTermScore = 0.0;
    final seen = <String>{};

    for (final term in behavior.allMatchTerms) {
      final n = normalize(term);
      if (n.isEmpty || !seen.add(n)) continue;
      if (q.contains(n)) {
        // 长词条更具体，权重按长度平方根增长但设上限，避免长别名一票压死。
        final w = math.sqrt(n.length.toDouble()).clamp(1.0, 3.2).toDouble();
        raw += w;
        hits.add(term);
        if (w > bestTermScore) {
          bestTermScore = w;
          bestTerm = term;
        }
      }
    }

    // 完全相等给一个显著加成（"深蹲" vs "今天做了深蹲"）。
    for (final alias in behavior.aliases) {
      if (normalize(alias) == q) {
        raw += 3.5;
        break;
      }
    }

    if (raw <= 0) {
      return MatchResult(behavior: behavior, score: 0, hits: const []);
    }

    // 压到 0–1：命中 1 个两字词约 0.34，命中 3 个词约 0.6，完全相等约 0.85。
    final score = raw / (raw + 2.0);
    final prefill = <String, String>{};
    final table = _prefills[behavior.code];
    if (table != null && bestTerm.isNotEmpty) {
      for (final entry in table.entries) {
        if (normalize(bestTerm).contains(normalize(entry.key)) ||
            normalize(entry.key).contains(normalize(bestTerm))) {
          prefill.addAll(entry.value);
          break;
        }
      }
    }

    return MatchResult(
      behavior: behavior,
      score: score.clamp(0, 1).toDouble(),
      hits: hits,
      prefill: prefill,
    );
  }

  /// 给候选卡用的一句话解释。绝不显示"匹配度 63%"这种数字。
  String explain(MatchResult r) {
    if (r.hits.isEmpty) return '可能相关';
    final top = r.hits.take(2).join('、');
    return '听到了「$top」';
  }

  /// 首页快捷短语 → 预填答案。
  static const List<String> quickPhrases = [
    '和昨天一样',
    '一组深蹲',
    '背单词',
    '昨晚几点睡',
    '今天没练',
    '跑步 30 分钟',
  ];
}

/// 让 UI 少写一层判空。
extension MatchListX on List<MatchResult> {
  bool get hasCandidate => isNotEmpty;

  MatchResult? get top => isEmpty ? null : first;
}

/// 便于测试：把一句话直接映射到 code。
String? resolveCode(IntentMatcher m, String input) {
  final r = m.match(input, limit: 1);
  return r.isEmpty ? null : r.first.behavior.code;
}

/// 便于测试：显式引用哨兵，避免 linter 报未使用。
const String kUnknownSentinelRef = kUnknownValue;
