/// 行为库 → 刻度标定层的适配。
///
/// 放在 presentation 而不是 domain/anchor：anchor 层不认识 28 条行为库
/// （那会让一个通用插件依赖具体业务），这里做单向适配。
///
/// 分类规则（可解释、可改）：
///   - 负向 / 计划外 → 半可观测（拖延、刷手机、熬夜：看时间占比，不给精确分）
///   - 正向且带问答（有可测的量）→ 可公式化
///   - 其余正向 → 仅主观可辨（深谈、正念、家务、育儿）
library;

import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';

class AnchorCatalog {
  AnchorCatalog({BehaviorLibrary? library})
      : library = library ?? BehaviorLibrary();

  final BehaviorLibrary library;

  /// 可以标定的行为（用户能直接录入的那些）。
  List<BehaviorDef> get candidates => library.captureable;

  MeasurementClass classOf(BehaviorDef b) {
    if (b.category != BehaviorCategory.positive) {
      return MeasurementClass.semiObservable;
    }
    if (b.questions.isNotEmpty) return MeasurementClass.formula;
    return MeasurementClass.subjective;
  }

  String? labelOf(String code) => library.byCode(code)?.name;

  /// 引导流程第一步的选项。
  List<OnboardingSelection> selections() => candidates
      .map((BehaviorDef b) => OnboardingSelection(
            behaviorId: b.code,
            label: b.name,
            measurementClass: classOf(b),
            hint: b.standardDefinition,
          ))
      .toList(growable: false);

  /// 允许 AI 引用的参照区间。同一分类下的区间都给它，让它自己挑。
  List<String> rangeIdsFor(String code) {
    final BehaviorDef? b = library.byCode(code);
    final MeasurementClass cls =
        b == null ? MeasurementClass.subjective : classOf(b);
    final List<ReferenceRange> ranges = referenceRangesFor(cls);
    return ranges.map((ReferenceRange r) => r.id).toList(growable: false);
  }

  /// 导出给网页 AI 的任务清单。
  List<ProposalTarget> targets(
    List<String> codes, {
    Map<String, UserAnchor> anchors = const <String, UserAnchor>{},
  }) {
    final List<ProposalTarget> out = <ProposalTarget>[];
    for (final String code in codes) {
      final BehaviorDef? b = library.byCode(code);
      if (b == null) continue;
      out.add(ProposalTarget(
        behaviorId: code,
        label: b.name,
        measurementClass: classOf(b),
        rangeIds: rangeIdsFor(code),
        existingUnitLabel: anchors[code]?.unitLabel ?? '',
      ));
    }
    return out;
  }

  /// 卡片标题：优先行为库里的中文名，查不到就退回 code。
  String titleOf(String code) => labelOf(code) ?? code;
}
