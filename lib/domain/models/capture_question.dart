import '../enums.dart';

/// 单个问题选项。按钮化优先：能点就不让打字。
class QuestionOption {
  const QuestionOption(
    this.value,
    this.label, {
    this.sublabel,
    this.numeric,
    this.hint,
  });

  /// 落库用的稳定值（英文/枚举串），绝不随文案变化。
  final String value;

  /// 屏上看到的字。
  final String label;

  /// 第二行小字，解释这个选项具体指什么。
  final String? sublabel;

  /// 选项自带的数值（如"12 次左右"=12）。
  final double? numeric;

  /// 选中后的即时提示。
  final String? hint;

  String get display => sublabel == null ? label : '$label · $sublabel';
}

/// 数字步进器的规格。始终给出"常规区间"，让用户知道自己在哪。
class NumberSpec {
  const NumberSpec({
    required this.min,
    required this.max,
    required this.initial,
    this.step = 1,
    this.unit = '',
    this.decimals = 0,
    this.presets = const [],
  });

  final double min;
  final double max;
  final double initial;
  final double step;
  final String unit;
  final int decimals;

  /// 常用值快捷键，如 [30, 40, 50, 60] kg。
  final List<double> presets;

  String format(double v) => '${v.toStringAsFixed(decimals)}$unit';
}

/// 一道题。一次只问一个关键变量。
class QuestionSpec {
  QuestionSpec({
    required this.id,
    required this.title,
    required this.why,
    required this.kind,
    this.options = const [],
    this.numberSpec,
    this.rangeHint,
    this.inheritFromLast = false,
    this.optional = false,
    this.showIf,
    this.unknownLabel = '不确定',
    this.assist,
  });

  /// 答案 map 的键。
  final String id;

  /// 大标题，≤12 字。
  final String title;

  /// 副标题：为什么问这个。一句人话，不堆术语。
  final String why;

  final QuestionKind kind;
  final List<QuestionOption> options;
  final NumberSpec? numberSpec;

  /// "常规 8–15 次"这类区间提示。
  final String? rangeHint;

  /// 是否提供"同上次"快捷继承。
  final bool inheritFromLast;

  /// 可跳过（跳过会把置信度压到 selfReport 并标注估算）。
  final bool optional;

  /// 条件显示：如"负重方式 = 自重"时不问重量。
  final bool Function(Map<String, Object?> answers)? showIf;

  /// 是否给"不确定"出口。给了就不阻塞。
  final String unknownLabel;

  /// 输入辅助说明（如"按手掌法：一掌心≈100g 肉"）。
  final String? assist;

  bool isVisible(Map<String, Object?> answers) => showIf?.call(answers) ?? true;

  QuestionOption? optionFor(String value) {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }
}

/// 答案读取的小工具，避免到处做类型判断。
extension AnswerMap on Map<String, Object?> {
  double? numOf(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  double numOr(String key, double fallback) => numOf(key) ?? fallback;

  String? strOf(String key) {
    final v = this[key];
    return v is String ? v : null;
  }

  bool isUnknown(String key) => this[key] == kUnknownValue;

  Map<String, Object?> merged(Map<String, Object?> other) => {
        ...this,
        ...other,
      };
}

/// "不确定"的统一哨兵值。任何行为收到它都必须降级置信度而非报错。
const String kUnknownValue = '__unknown__';
