/// 四道闸：口径能不能收、份额怎么纠正。
///
/// 规则顺序是契约的一部分：先判"这条能不能收"（形状参数、分母、量法匹配），
/// 再纠正份额（份额错了不影响能不能收，只影响怎么分）。
library;

import 'axis_registry.dart';
import 'dose_shape.dart';
import 'quant_measure.dart';
import 'quant_spec.dart';

/// 校验问题。`R_` = 整条打回，`T_` = 纠正后收下（与刻度层同一套观感）。
class QuantIssue {
  const QuantIssue({
    required this.code,
    required this.field,
    required this.message,
    this.slot = -1,
  });

  final String code;
  final String field;
  final String message;

  /// 在 AI 回复里的序号。用户能回去只让 AI 改那一条。
  final int slot;

  bool get isReject => code.startsWith('R_');

  @override
  String toString() =>
      '${slot >= 0 ? "#$slot " : ""}$code($field): $message';
}

/// 校验结果：纠正后的规格 + 问题清单。
class QuantValidation {
  const QuantValidation(this.spec, this.issues);

  final QuantSpec spec;
  final List<QuantIssue> issues;

  List<QuantIssue> get rejects =>
      issues.where((QuantIssue q) => q.isReject).toList(growable: false);

  bool get accepted => rejects.isEmpty;

  List<String> get notes => issues
      .where((QuantIssue q) => !q.isReject)
      .map((QuantIssue q) => q.message)
      .toList(growable: false);
}

/// 唯一校验入口。**顺序不可交换**：先判能不能收（量什么、形状参数、目标量、维度归属），
/// 再纠正份额（份额错了不影响"这条能不能收"，只影响怎么分）。
QuantValidation validateQuantSpec(
  QuantSpec spec, {
  AxisRegistry registry = const AxisRegistry(),
  int slot = -1,
}) {
  final List<QuantIssue> issues = <QuantIssue>[];

  if (spec.behaviorCode.trim().isEmpty) {
    issues.add(QuantIssue(
      code: 'R_NO_CODE',
      field: 'behavior_code',
      message: '缺少行为码',
      slot: slot,
    ));
  }

  // 1. 形状参数（由 DoseShapeSpec 自己判，这里只搬运）
  final ShapeVerdict shapeVerdict = spec.shape.validate();
  if (!shapeVerdict.accepted) {
    issues.add(QuantIssue(
      code: shapeVerdict.code,
      field: 'shape',
      message: shapeVerdict.note,
      slot: slot,
    ));
  }

  // 2. 目标量是分母，必须为正
  if (spec.targetDose <= 0) {
    issues.add(QuantIssue(
      code: 'R_TARGET_REQUIRED',
      field: 'target_dose',
      message: '目标量必须大于 0（它是折算的分母）',
      slot: slot,
    ));
  }

  // 3. 事件型必须靠阈值，时长型不许用阈值（两者是同一件事的两种说法）
  if (spec.measureKind == MeasureKind.episode &&
      spec.shape.kind != DoseShape.threshold) {
    issues.add(QuantIssue(
      code: 'T_SHAPE_FOR_EVENT',
      field: 'shape',
      message: '事件型行为建议用 threshold（要么发生要么没发生）',
      slot: slot,
    ));
  }
  if (spec.measureKind == MeasureKind.durationMin &&
      spec.shape.kind == DoseShape.threshold) {
    issues.add(QuantIssue(
      code: 'R_SHAPE_MISMATCH',
      field: 'shape',
      message: '时长型行为不能用事件型阈值（那会把"聊了 20 分钟"记成 0）',
      slot: slot,
    ));
  }

  // 4. 维度：份额归一 + 新维度降级 + 首版只允许一个能力维度
  final List<ImpactShare> normalized = <ImpactShare>[];
  double sum = 0;
  for (final ImpactShare s in spec.impact) {
    if (s.share <= 0) {
      issues.add(QuantIssue(
        code: 'T_SHARE_DROPPED',
        field: 'impact',
        message: '维度「${s.axisLabel}」份额为 0，已忽略',
        slot: slot,
      ));
      continue;
    }
    final AxisSpec? known = registry.tryResolve(s.axisKey);
    if (known == null) {
      // 新维度：只有自带衰减常数 + 依据才准进能力曲线，否则降成体验维度。
      // 这是这一层唯一不能被 AI 推翻的规则——说不出"为什么掉这么慢"，
      // 就只配进体验曲线。
      if (s.kind == AxisKind.ability && !s.hasDecayEvidence) {
        issues.add(QuantIssue(
          code: 'T_AXIS_DEMOTED',
          field: 'impact',
          message: '新维度「${s.axisLabel}」没有衰减依据，只进体验曲线',
          slot: slot,
        ));
        normalized.add(s.copyWith(kind: AxisKind.experience));
        sum += s.share;
        continue;
      }
      if (s.kind == AxisKind.ability) {
        issues.add(QuantIssue(
          code: 'T_AXIS_PROVISIONAL',
          field: 'impact',
          message: '新维度「${s.axisLabel}」按你给的衰减常数 '
              '${s.decayTauDays.toStringAsFixed(0)} 天先跑，等实测覆盖',
          slot: slot,
        ));
      }
    } else {
      // 已知维度以注册表为准：用户/AI 说了不算。
      if (known.kind != s.kind) {
        issues.add(QuantIssue(
          code: 'T_AXIS_KIND_FIXED',
          field: 'impact',
          message: '维度「${known.label}」的量纲按注册表为准（${known.kind.label}）',
          slot: slot,
        ));
      }
      normalized.add(ImpactShare(
        axisKey: known.key,
        axisLabel: known.label,
        kind: known.kind,
        share: s.share,
      ));
      sum += s.share;
      continue;
    }
    normalized.add(s);
    sum += s.share;
  }

  if (normalized.isEmpty) {
    issues.add(QuantIssue(
      code: 'R_NO_IMPACT',
      field: 'impact',
      message: '至少要说清这条影响落在哪个维度',
      slot: slot,
    ));
  } else if ((sum - 1).abs() > 0.01) {
    // 不静默：份额不对要纠正，但要让用户看见"我把它按比例改了"。
    final List<ImpactShare> fixed = normalized
        .map((ImpactShare s) => s.copyWith(share: s.share / sum))
        .toList(growable: false);
    issues.add(QuantIssue(
      code: 'T_SHARE_RENORMALIZED',
      field: 'impact',
      message: '份额合计 ${sum.toStringAsFixed(2)}，已按比例归一到 1',
      slot: slot,
    ));
    normalized
      ..clear()
      ..addAll(fixed);
  }

  final List<ImpactShare> abilityShares =
      normalized.where((ImpactShare s) => s.kind == AxisKind.ability).toList();
  if (abilityShares.length > 1) {
    issues.add(QuantIssue(
      code: 'R_MULTI_ABILITY_UNSUPPORTED',
      field: 'impact',
      message: '首版只支持一个能力维度（多轴分摊要改 valence_event 唯一约束，暂不做）',
      slot: slot,
    ));
  }

  // 5. 主观分只能进体验维度：它不是剂量，没有分母
  if (spec.measureKind == MeasureKind.rating && abilityShares.isNotEmpty) {
    issues.add(QuantIssue(
      code: 'R_RATING_NOT_ABILITY',
      field: 'measure_kind',
      message: '主观分不能推能力值（自报的 8 分不等于练了 8 分）',
      slot: slot,
    ));
  }

  return QuantValidation(
    spec.copyWith(impact: normalized),
    issues,
  );
}
