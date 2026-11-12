import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';

/// 回执的视图模型。UI 只负责把它画出来，不再做任何判断。
class ReceiptView {
  const ReceiptView({
    required this.title,
    required this.interpretation,
    required this.lines,
    required this.confidence,
    required this.confidenceLine,
    required this.valence,
    required this.notes,
    required this.warnings,
    required this.footnote,
    this.showNeutralBanner = false,
  });

  final String title;
  final String interpretation;
  final List<ReceiptLine> lines;
  final Confidence confidence;

  /// "置信度：中（自报）—— 这些数是你自己填的，没有实测支撑。"
  final String confidenceLine;

  final Valence valence;
  final List<String> notes;
  final List<String> warnings;

  /// 底部一句：不催促、不夸奖，只说明可以改。
  final String footnote;

  /// 中性横幅：行为价既非正也非负时（如蛋白质刚好卡在中间）。
  final bool showNeutralBanner;

  bool get isNegative => valence == Valence.negative;

  bool get isOffPlan => valence == Valence.offPlan;
}

/// 把 DerivedResult 组装成一句人话 + 四五行数据 + 置信度说明。
///
/// 回执的语言规则（写进代码里，避免以后被改坏）：
///   · 只用"系统理解成 / 估算 / 约 / 折算"这类中性动词。
///   · 不用"优秀/糟糕/失败/不足"这类评价词。
///   · 负向回执不出现任何感叹号。
class ReceiptBuilder {
  const ReceiptBuilder();

  ReceiptView build({
    required BehaviorDef behavior,
    required DerivedResult derived,
    required Valence valence,
    List<String> extraNotes = const [],
  }) {
    final confidence = derived.confidence;
    return ReceiptView(
      title: '系统理解成了什么',
      interpretation: derived.interpretation,
      lines: derived.lines,
      confidence: confidence,
      confidenceLine: '置信度：${confidence.receiptLabel} · ${_confidenceWhy(confidence)}',
      valence: valence,
      notes: [...derived.notes, ...extraNotes],
      warnings: derived.warnings,
      footnote: _footnoteFor(valence),
      showNeutralBanner: valence == Valence.neutral,
    );
  }

  String _confidenceWhy(Confidence c) => switch (c) {
        Confidence.selfReport => '这些数是你自己填的，没有实测支撑',
        Confidence.formula => '由你其他数据推算得出，受公式误差影响',
        Confidence.calibrated => '来自你的实测校准，可信度最高',
      };

  String _footnoteFor(Valence v) => switch (v) {
        Valence.negative => '这条会记进账本，不评价你，只标出后果和怎么回补。',
        Valence.offPlan => '计划外的事单独处理，不会直接变成加减分。',
        _ => '数字只是估算，不对就点"改一下"。',
      };

  /// 负向回执的标题用中性措辞，绝不出现"警告""失败"。
  String headerFor(Valence v) => switch (v) {
        Valence.negative => '这条记录的后果',
        Valence.offPlan => '这件事怎么算',
        _ => '系统理解成了什么',
      };

  /// 回执里那行"1 组深蹲 ≈ 12 次 @60kg"的兜底：
  /// 如果行为自己没给 interpretation，用第一行的值拼一句。
  String ensureInterpretation(DerivedResult d, BehaviorDef b) {
    if (d.interpretation.trim().isNotEmpty) return d.interpretation;
    if (d.lines.isEmpty) return b.name;
    final first = d.lines.first;
    return '${b.name}：${first.value}';
  }

  /// 用户点"不确定"时补的一句说明。
  String unknownExplanation() => '你选了"说不好"，这一项按常规值估算，置信度会标成自报。';
}

/// 把答案里出现过的"不确定"挑出来，用于回执上标注哪几项是估的。
List<String> unknownAnswerLabels(
  Map<String, Object?> answers,
  BehaviorDef behavior,
) {
  final labels = <String>[];
  for (final q in behavior.questions) {
    if (answers.isUnknown(q.id)) labels.add(q.title);
  }
  return labels;
}
