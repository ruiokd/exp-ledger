import '../../core/config/balance_config.dart';
import '../enums.dart';
import 'capture_question.dart';
import 'project_axis.dart';
import 'user_profile.dart';

/// 回执里的一行。label 左、value 右，emphasis 的行加粗。
class ReceiptLine {
  const ReceiptLine(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;
}

/// 推导过程需要的全部上下文。
///
/// 注意：derive 必须是纯函数——同样的 ctx 必须得到同样的结果，
/// 否则"历史修正后级联重算"会不收敛。
class DeriveContext {
  const DeriveContext({
    required this.answers,
    required this.profile,
    required this.config,
    required this.now,
    this.lastAnswers,
    this.confidenceCeiling = Confidence.calibrated,
  });

  /// 本次问答的原始答案（键为 QuestionSpec.id）。
  final Map<String, Object?> answers;
  final UserProfile profile;
  final BalanceConfig config;
  final DateTime now;

  /// 上一次同行为的答案，用于"同上次"继承与对比。
  final Map<String, Object?>? lastAnswers;

  /// 置信度上限：出现过"不确定"或"跳过"时由状态机压到 selfReport。
  final Confidence confidenceCeiling;

  double numOr(String key, double fallback) => answers.numOr(key, fallback);

  double? numOf(String key) => answers.numOf(key);

  String strOr(String key, String fallback) => answers.strOf(key) ?? fallback;

  int intOr(String key, int fallback) => numOr(key, fallback.toDouble()).round();

  bool flagOr(String key, bool fallback) {
    final v = answers[key];
    if (v is bool) return v;
    if (v is String) return v == 'true' || v == 'yes';
    return fallback;
  }

  bool isUnknown(String key) => answers.isUnknown(key);

  /// 本行为是否由用户主动上报（自报）还是由系统从别的数据推导。
  Confidence resolveConfidence(Confidence natural) =>
      Confidence.min(natural, confidenceCeiling);
}

/// derive 的函数签名。
typedef DeriveFn = DerivedResult Function(DeriveContext ctx);

/// 一次行为推导的产物。UI 用它渲染回执，仓储用它落库。
class DerivedResult {
  const DerivedResult({
    required this.slotKey,
    required this.interpretation,
    required this.lines,
    required this.metrics,
    required this.normalized,
    required this.confidence,
    required this.doseFraction,
    this.notes = const [],
    this.warnings = const [],
  });

  /// 幂等键的组成部分之一：同一天同一行为同一槽位只会有一行。
  /// 例如一次训练拆成多个动作时，用动作名做 slot 的后缀。
  final String slotKey;

  /// "系统理解成了什么"——一句话，不用术语。
  final String interpretation;

  /// 回执正文四行左右。
  final List<ReceiptLine> lines;

  /// 中间量（kcal、有效组、保持率……）落库后供图表与明细页使用。
  final Map<String, double> metrics;

  /// 归一化后的回答，原始 JSON 落库。
  final Map<String, Object?> normalized;

  final Confidence confidence;

  /// 0–1，达到该行为目标剂量的比例。低于 1 不代表失败，只代表"部分剂量"。
  final double doseFraction;

  /// 中性提示（如"你填的重量比上次高 10%"）。
  final List<String> notes;

  /// 需要用户注意的事（如"这已经接近你的安全上限"）。
  final List<String> warnings;

  bool get isNegative => metrics['exp_sign'] == -1;
}

/// 行为定义。一条 [BehaviorDef] 就是行为库里的一个完整条目。
class BehaviorDef {
  const BehaviorDef({
    required this.code,
    required this.name,
    required this.category,
    required this.valence,
    required this.axis,
    required this.aliases,
    required this.standardDefinition,
    required this.misconception,
    required this.questions,
    required this.derive,
    this.keywords = const [],
    this.minEffectiveDose = 1,
    this.targetDose = 1,
    this.doseUnit = '次',
    this.defaultConfidence = Confidence.selfReport,
    this.needsPlanGate = false,
    this.slotScope = SlotScope.perDay,
    this.iconName = 'dot',
    this.resolveValence,
    this.userCaptureable = true,
  });

  /// 稳定的机器码，落库与规则匹配都用它，永远不改。
  final String code;

  /// 屏上显示的中文名。
  final String name;

  final BehaviorCategory category;
  final Valence valence;
  final ProjectAxis axis;

  /// 意图匹配用的别名（含口语说法）。
  final List<String> aliases;

  /// 额外的匹配关键词（动词、部位、场景）。
  final List<String> keywords;

  /// 标准定义：用可判定语言说明"什么算 1 组 / 1 次 / 1 小时有效"。
  final String standardDefinition;

  /// 常见误区提示：在问题页底部以淡字出现，不说教。
  final String misconception;

  final List<QuestionSpec> questions;
  final DeriveFn derive;

  final double minEffectiveDose;
  final double targetDose;
  final String doseUnit;
  final Confidence defaultConfidence;

  /// 是否需要先问"是否在原计划内"。
  final bool needsPlanGate;

  /// 幂等粒度：按天覆盖，还是按天+槽位覆盖（如多个训练动作）。
  final SlotScope slotScope;

  /// 图标语义名（UI 层映射到具体 IconData，domain 不依赖 Flutter）。
  final String iconName;

  /// 动态价：有些行为同一次录入既可能是正向也可能是负向（睡眠、饮食）。
  /// 给了这个函数就由推导结果决定 valence，静态 [valence] 只作为兜底。
  final Valence Function(DerivedResult)? resolveValence;

  /// 是否允许用户直接录入。为 false 的行为只能由其他数据推导
  /// （例：睡眠不足由睡眠流程自动派生，避免与熬夜双计）。
  final bool userCaptureable;

  /// 推导完成后确定最终 valence。
  Valence valenceOf(DerivedResult d) => resolveValence?.call(d) ?? valence;

  /// 参与模糊匹配的全部词条。
  List<String> get allMatchTerms => [...aliases, ...keywords, name];

  /// 取第一道可见问题。
  QuestionSpec? firstQuestion() {
    for (final q in questions) {
      if (q.isVisible(const {})) return q;
    }
    return questions.isEmpty ? null : questions.first;
  }

  @override
  bool operator ==(Object other) => other is BehaviorDef && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'BehaviorDef($code)';
}

/// 幂等粒度。
enum SlotScope {
  /// 同一天同一行为只有一条（睡眠、饮食这类天然一天一次）。
  perDay,

  /// 同一天同一行为可以有多个槽位（每个动作/每个食物条目一条）。
  perSlot,
}
