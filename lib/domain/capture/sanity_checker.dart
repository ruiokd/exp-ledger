import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';

/// 合理性校验：只在"明显不像真的"时轻轻提示一句，绝不阻断。
///
/// 三条原则：
///   1. 阈值必须是生理上真的离谱（体重 3 倍以上的深蹲、一次 300 个单词）。
///   2. 提示必须是疑问句，不是判决。
///   3. 永远保留"我知道我在做什么"的出口——用户自己的数据，他比我更有资格判断。
class SanityChecker {
  const SanityChecker();

  List<SanityIssue> check({
    required BehaviorDef behavior,
    required Map<String, Object?> answers,
    required UserProfile profile,
  }) {
    final issues = <SanityIssue>[];
    final code = behavior.code;
    if (code == 'strength_training') {
      _checkStrength(answers, profile, issues);
    } else if (code == 'sleep') {
      _checkSleep(answers, profile, issues);
    } else if (code == 'vocabulary_review') {
      final words = answers.numOf('words');
      if (words != null && words > 300) {
        issues.add(SanityIssue(
          questionId: 'words',
          message: '一次 ${words.toInt()} 个词，听起来更像是把这周的总量一起记了？',
          suggestion: '拆成每天的量，曲线会好看得多',
        ));
      }
    } else if (code == 'cardio') {
      final minutes = answers.numOf('minutes');
      if (minutes != null && minutes > 240) {
        issues.add(const SanityIssue(
          questionId: 'minutes',
          message: '超过 4 小时的连续有氧，是比赛日吗？',
          suggestion: '如果是分段完成的，按主要那一段记就够',
        ));
      }
    } else if (code == 'alcohol_over') {
      final drinks = answers.numOf('drinks');
      if (drinks != null && drinks >= 10) {
        issues.add(SanityIssue(
          questionId: 'drinks',
          message: '${drinks.toInt()} 标准杯对身体是很大的负担，注意别一个人待着。',
          suggestion: '如果出现呕吐、意识模糊，请让人陪着并及时就医',
        ));
      }
    }
    return issues;
  }

  void _checkStrength(
    Map<String, Object?> answers,
    UserProfile profile,
    List<SanityIssue> issues,
  ) {
    final weight = answers.numOf('weight') ?? 0;
    final reps = answers.numOf('reps') ?? 0;
    final sets = answers.numOf('sets') ?? 0;
    final ceiling = profile.weightKg * 3.0;
    if (weight > ceiling) {
      issues.add(SanityIssue(
        questionId: 'weight',
        message:
            '${weight.toStringAsFixed(0)}kg 超过你体重的 3 倍（${ceiling.toStringAsFixed(0)}kg），确认一下单位是公斤吗？',
        suggestion: '很多人这里填的是"磅"',
      ));
    }
    if (reps > 50) {
      issues.add(SanityIssue(
        questionId: 'reps',
        message: '一组 ${reps.toInt()} 次，超出常规很多，是分几组做的吗？',
        suggestion: '如果确实是耐力组，保持原样即可',
      ));
    }
    if (sets > 12) {
      issues.add(SanityIssue(
        questionId: 'sets',
        message: '${sets.toInt()} 组，这个量已经相当大，恢复跟得上吗？',
      ));
    }
  }

  void _checkSleep(
    Map<String, Object?> answers,
    UserProfile profile,
    List<SanityIssue> issues,
  ) {
    final bed = answers.strOf('bed');
    final wake = answers.strOf('wake');
    if (bed != null && wake != null && bed == wake) {
      issues.add(const SanityIssue(
        questionId: 'wake',
        message: '入睡和醒来时间一样，是没睡，还是填错了？',
        suggestion: '如果确实没睡，把这一项留空更准确',
      ));
    }
  }
}
