/// 问题构造的小 DSL。把"写一道题"压缩到一行，
/// 让行为库里的 28 个条目都能保持可读，而不是被样板代码埋掉。
library;

import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';

/// 单选问题。
QuestionSpec choiceQ(
  String id,
  String title,
  String why,
  List<QuestionOption> options, {
  String? rangeHint,
  bool inherit = false,
  bool optional = false,
  bool allowUnknown = true,
  bool Function(Map<String, Object?>)? showIf,
  String? assist,
}) {
  final opts = <QuestionOption>[...options];
  if (allowUnknown) {
    opts.add(const QuestionOption(kUnknownValue, '说不好', sublabel: '按常规估'));
  }
  return QuestionSpec(
    id: id,
    title: title,
    why: why,
    kind: QuestionKind.choice,
    options: opts,
    rangeHint: rangeHint,
    inheritFromLast: inherit,
    optional: optional,
    showIf: showIf,
    assist: assist,
  );
}

/// 数字步进问题。
QuestionSpec numQ(
  String id,
  String title,
  String why, {
  required double min,
  required double max,
  required double initial,
  double step = 1,
  String unit = '',
  String? rangeHint,
  bool inherit = true,
  int decimals = 0,
  List<double> presets = const [],
  bool Function(Map<String, Object?>)? showIf,
  String? assist,
}) {
  return QuestionSpec(
    id: id,
    title: title,
    why: why,
    kind: QuestionKind.number,
    rangeHint: rangeHint,
    inheritFromLast: inherit,
    numberSpec: NumberSpec(
      min: min,
      max: max,
      initial: initial,
      step: step,
      unit: unit,
      decimals: decimals,
      presets: presets,
    ),
    showIf: showIf,
    assist: assist,
  );
}

/// 时长问题（分钟）。
QuestionSpec minutesQ(
  String id,
  String title,
  String why, {
  double initial = 30,
  double max = 480,
  String? rangeHint,
  bool inherit = true,
}) =>
    numQ(
      id,
      title,
      why,
      min: 1,
      max: max,
      initial: initial,
      step: 5,
      unit: ' 分钟',
      rangeHint: rangeHint,
      inherit: inherit,
      presets: const [10, 20, 30, 45, 60, 90],
    );

/// 时间点问题（HH:mm）。
QuestionSpec timeQ(
  String id,
  String title,
  String why, {
  required String initial,
  bool inherit = true,
}) {
  final parts = initial.split(':');
  final minutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
  return QuestionSpec(
    id: id,
    title: title,
    why: why,
    kind: QuestionKind.timeOfDay,
    inheritFromLast: inherit,
    numberSpec: NumberSpec(
      min: 0,
      max: 1439,
      initial: minutes.toDouble(),
      step: 5,
      unit: '',
    ),
  );
}

/// 通用"剂量型"推导：只关心"做了多少 vs 目标多少"的行为都用它。
DerivedResult buildDoseResult({
  required DeriveContext ctx,
  required String slotKey,
  required double dose,
  required double target,
  required String unit,
  required String interpretation,
  required List<ReceiptLine> lines,
  Map<String, double> metrics = const {},
  List<String> notes = const [],
  List<String> warnings = const [],
  Confidence confidence = Confidence.selfReport,
  int sign = 1,
}) {
  final frac = target <= 0 ? 0.0 : (dose / target).clampRange(0, 3);
  return DerivedResult(
    slotKey: slotKey,
    interpretation: interpretation,
    lines: lines,
    metrics: {
      'dose': dose,
      'target': target,
      'exp_sign': sign.toDouble(),
      ...metrics,
    },
    normalized: {...ctx.answers},
    confidence: ctx.resolveConfidence(confidence),
    doseFraction: frac,
    notes: notes,
    warnings: warnings,
  );
}
