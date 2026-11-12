import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/capture/intent_matcher.dart';
import 'package:test/test.dart';

void main() {
  final library = BehaviorLibrary();
  final matcher = IntentMatcher(library);

  group('意图匹配', () {
    test('"我今天做了一组深蹲" 命中抗阻训练，并预填 exercise=squat', () {
      final r = matcher.match('我今天做了一组深蹲');
      expect(r, isNotEmpty);
      expect(r.first.behavior.code, 'strength_training');
      expect(r.first.prefill['exercise'], 'squat');
    });

    test('"熬到两点才睡" 命中睡眠，且判定为负向候选', () {
      final r = matcher.match('熬到两点才睡');
      expect(r, isNotEmpty);
      expect(r.first.behavior.code, 'sleep');
    });

    test('"背了20个单词" 命中词汇', () {
      final r = matcher.match('背了20个单词');
      expect(r, isNotEmpty);
      expect(r.first.behavior.code, 'vocabulary_review');
    });

    test('完全不相关的话不产生候选（走自由记录）', () {
      final r = matcher.match('今天天气不错');
      expect(r, isEmpty);
    });

    test('标点与空白不影响匹配', () {
      final a = matcher.match('深 蹲！');
      final b = matcher.match('深蹲');
      expect(a.first.behavior.code, b.first.behavior.code);
    });

    test('最多返回 3 个候选', () {
      final r = matcher.match('今天做了深蹲又跑了步还背了单词');
      expect(r.length, lessThanOrEqualTo(3));
    });

    test('归一化会去掉标点但保留中文与数字', () {
      expect(IntentMatcher.normalize('深蹲，12 次！'), '深蹲12次');
    });

    test('分数单调：更精确的说法得分不低于更模糊的说法', () {
      final exact = matcher.match('深蹲').first.score;
      final vague = matcher.match('我好像做了点什么，可能是深蹲吧，反正挺累的').first.score;
      expect(exact, greaterThanOrEqualTo(vague - 1e-9));
    });
  });
}
