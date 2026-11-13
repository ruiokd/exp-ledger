import 'package:exp_ledger/domain/behaviors/negative/negative_others.dart';
import 'package:exp_ledger/domain/behaviors/offplan/offplan.dart';
import 'package:exp_ledger/domain/behaviors/positive/positive_others.dart';
import 'package:exp_ledger/domain/behaviors/positive/strength_training.dart';
import 'package:exp_ledger/domain/behaviors/positive/vocabulary_review.dart';
import 'package:exp_ledger/domain/behaviors/sleep_record.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';

/// 行为库。全部内置、可扩展、正负与计划外三类齐备。
///
/// 扩展方式：新建一个 BehaviorDef 常量，加进 [all] 即可——
/// 意图匹配、引导问答、回执、结算都会自动接上，不需要改状态机。
class BehaviorLibrary {
  BehaviorLibrary({List<BehaviorDef>? extra})
      : all = <BehaviorDef>[
          strengthTrainingBehavior,
          vocabularyReviewBehavior,
          sleepBehavior,
          ...positiveOthers,
          ...negativeOthers,
          ...offPlanBehaviors,
          ...?extra,
        ] {
    for (final b in all) {
      _byCode[b.code] = b;
    }
  }

  final List<BehaviorDef> all;
  final Map<String, BehaviorDef> _byCode = {};

  /// 可以被用户直接录入的行为（排除只能派生的条目）。
  List<BehaviorDef> get captureable =>
      all.where((b) => b.userCaptureable).toList(growable: false);

  List<BehaviorDef> byCategory(BehaviorCategory c) =>
      all.where((b) => b.category == c).toList(growable: false);

  /// 运行期注册（自建项目）。
  ///
  /// 故意**不重建对象**：CaptureMachine / IntentMatcher 持有的是同一个实例，
  /// 原地加进 [all] 与索引后，它们立刻就能匹配到新行为。
  void register(List<BehaviorDef> extra) {
    for (final BehaviorDef b in extra) {
      if (_byCode.containsKey(b.code)) continue;
      all.add(b);
      _byCode[b.code] = b;
    }
  }

  BehaviorDef? byCode(String code) => _byCode[code];

  BehaviorDef require(String code) {
    final b = _byCode[code];
    if (b == null) {
      throw StateError('行为库里没有这个 code：$code');
    }
    return b;
  }

  /// 首页"常用"区：按使用频次由仓储层传进来，这里只负责兜底排序。
  List<BehaviorDef> quickPicks({List<String> preferredCodes = const []}) {
    final result = <BehaviorDef>[];
    for (final code in preferredCodes) {
      final b = _byCode[code];
      if (b != null && b.userCaptureable && !result.contains(b)) {
        result.add(b);
      }
    }
    const fallback = ['strength_training', 'sleep', 'vocabulary_review'];
    for (final code in fallback) {
      final b = _byCode[code];
      if (b != null && !result.contains(b)) result.add(b);
    }
    return result.take(6).toList(growable: false);
  }
}
