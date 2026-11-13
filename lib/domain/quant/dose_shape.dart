/// 量化形状：把「这次做了多少」映射成 `doseFraction` 的那一段。
///
/// 这一层只回答一个问题：**没做满的时候，算几成？**
///
/// 归一化约定（这一层的全部意义所在）：
/// 所有形状都满足 `f(target) == 1.0`，所以 `baseScoreFor` / 质量加成 /
/// 效率加成 / 状态乘数 / 置信权重一个都不用改。形状只改 `dose < target`
/// 那一段的斜率，不改满分线。
///
/// 不允许在这里算 EXP，也不允许出现裸的分值系数——这里只有形状。
library;

import 'dart:math' as math;

/// 四种形状。第五种 biphasic（好事过头反噬）故意没做：
/// 负向已经有独立的 category + negativeCurve，一个形状同时产出正负
/// 会打破「负向不乘状态乘数」这条铁律。
enum DoseShape {
  /// 线性累积：做得越多越好。默认形状，也是 v1.1.x 的唯一行为。
  linear('线性', '做多少算多少，按比例'),

  /// 边际递减：前段有效，后段越来越不值。
  log('对数递减', '开头最有用，后面越来越不值'),

  /// 饱和：有生理或时间上限，超出目标几乎不再增加。
  saturating('饱和', '有上限，接近目标就到顶了'),

  /// 事件型：要么发生要么没发生，不存在「做一半」。
  threshold('事件型', '发生了就算完成，不做一半');

  const DoseShape(this.label, this.semantics);

  final String label;
  final String semantics;

  static DoseShape? tryParse(String? raw) {
    if (raw == null) return null;
    for (final DoseShape s in DoseShape.values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  /// 缺省形状：库里已有的自建项目没有形状字段，一律按线性走，
  /// 所以升级不会让任何一条历史记录的分变化。
  static DoseShape parseOrDefault(String? raw) => tryParse(raw) ?? linear;
}

/// 参数校验的结果码。与刻度层的 `R_*` / `T_*` 前缀保持同一套观感：
/// `R_` = 整条打回，`T_` = 降档/纠正后收下。
class ShapeVerdict {
  const ShapeVerdict.ok(this.note) : code = '';

  const ShapeVerdict.reject(this.code, this.note);

  final String code;
  final String note;

  bool get accepted => code.isEmpty;

  static const ShapeVerdict _ok = ShapeVerdict.ok('');

  @override
  String toString() => accepted ? 'ok' : '$code: $note';
}

/// 形状规格。AI 只被允许说「哪种形状 + 哪一个档位参数」，
/// 不允许给任意实数，所以参数都被收成有限集合。
class DoseShapeSpec {
  const DoseShapeSpec({
    required this.kind,
    this.logK = 1.0,
    this.thetaFraction = 1.0,
  });

  const DoseShapeSpec.linear()
      : kind = DoseShape.linear,
        logK = 1.0,
        thetaFraction = 1.0;

  final DoseShape kind;

  /// 仅 [DoseShape.log] 用。允许值只有 [allowedLogK] 里的四档。
  final double logK;

  /// 仅 [DoseShape.threshold] 用，表示阈值是目标量的几倍。
  /// 允许值只有 1.0 与 0.5——写绝对值会在用户改目标量后错位。
  final double thetaFraction;

  /// 对数的四档。给档位而不是给范围，是为了让「AI 说 k=0.37」这种
  /// 无法核对的东西在入口就进不来。
  static const List<double> allowedLogK = <double>[0.5, 1, 2, 4];

  /// 阈值的两档。
  static const List<double> allowedThetaFraction = <double>[0.5, 1];

  static DoseShapeSpec parseOrDefault(Map<String, Object?>? raw) {
    if (raw == null) return const DoseShapeSpec.linear();
    final DoseShape kind = DoseShape.parseOrDefault(raw['kind']?.toString());
    final double k = _asDouble(raw['k'], 1.0);
    final double theta = _asDouble(raw['theta_fraction'], 1.0);
    return DoseShapeSpec(kind: kind, logK: k, thetaFraction: theta);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        if (kind == DoseShape.log) 'k': logK,
        if (kind == DoseShape.threshold) 'theta_fraction': thetaFraction,
      };

  /// 把「本次量 / 目标量」这两个原始数压成一个 0–1.x 的系数。
  ///
  /// 不夹上限：超额那一段由 `baseScoreFor` + 效率加成处理，
  /// 在这里夹会吃掉「多做了」的信号。调用方（`customBehaviorDef.derive`）
  /// 照旧按 1.5 封顶。
  double fractionFor(double dose, double target) {
    final double t = target > 0 ? target : 1;
    final double d = dose < 0 ? 0 : dose;

    // 用 if/else 链而不是 switch：本仓库的惯例（见 STATE 七），
    // 也方便将来加第五种形状时只加一支。
    if (kind == DoseShape.log) {
      final double k = _nearestAllowed(logK, allowedLogK, 1);
      // 关键：k 必须无量纲，作用在 `d/t` 上，而不是作用在绝对量上。
      //
      // 错误写法 `ln(1+kd)/ln(1+kt)` 在 d==t 时确实为 1，但它**不是尺度不变的**：
      // 目标量 40 分钟时做一半得 0.82，目标量 1 次时得 0.585。
      // 那样一来「改一下目标量」会悄悄改掉这条曲线的形状，而界面上看不出任何变化。
      // 写成 `ln(1+k·d/t)/ln(1+k)` 后，目标量只改分母刻度，形状由 k 唯一决定。
      final double ratio = d / t;
      return math.log(1 + k * ratio) / math.log(1 + k);
    }
    if (kind == DoseShape.saturating) {
      // 米氏型，K = t/3 时 t 处正好到 1（已归一化）。K 不是自由参数：
      // 它跟着目标量走，用户改目标量不会把曲线形状改坏。
      final double kk = t / 3;
      final double at = t / (t + kk);
      if (at <= 0) return 0;
      return (d / (d + kk)) / at;
    }
    if (kind == DoseShape.threshold) {
      final double theta =
          t * _nearestAllowed(thetaFraction, allowedThetaFraction, 1);
      return d + 1e-9 >= theta ? 1.0 : 0.0;
    }
    return d / t;
  }

  /// 四道闸里的两道（另两道在 `quant_spec` 的份额与维度校验里）。
  ShapeVerdict validate() {
    if (kind == DoseShape.log) {
      if (!allowedLogK.contains(logK)) {
        return ShapeVerdict.reject(
          'R_FREE_PARAM',
          '对数的 k 只接受 ${allowedLogK.join(" / ")}，收到 $logK',
        );
      }
    }
    if (kind == DoseShape.threshold) {
      if (!allowedThetaFraction.contains(thetaFraction)) {
        return ShapeVerdict.reject(
          'R_FREE_PARAM',
          '阈值只接受目标量的 ${allowedThetaFraction.join(" / ")} 倍，收到 $thetaFraction',
        );
      }
    }
    return ShapeVerdict._ok;
  }

  /// 回执上的那一行说明：让用户看得见「为什么做一半只算六成」。
  String describe(double dose, double target) {
    final double t = target > 0 ? target : 1;
    if (kind == DoseShape.log) {
      return '递减计（k=${_fmt(logK)}）：前段更值钱';
    }
    if (kind == DoseShape.saturating) {
      return '饱和计：接近目标就到顶';
    }
    if (kind == DoseShape.threshold) {
      final double theta = t * thetaFraction;
      return '事件型：达到 ${_fmt(theta)} 才算完成';
    }
    return '按比例计：${_fmt(dose)}/${_fmt(t)}';
  }
}

double _asDouble(Object? raw, double fallback) {
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final double? v = double.tryParse(raw);
    if (v != null) return v;
  }
  return fallback;
}

/// 取最近的允许值。故意「就近收敛」而不是打回：
/// 参数只影响形状不影响力，为了一个 k=0.9 整条拒收是过度惩罚。
/// 真正的打回在 [DoseShapeSpec.validate] 里，由调用方决定要不要用。
double _nearestAllowed(double value, List<double> allowed, double fallback) {
  if (allowed.isEmpty) return fallback;
  double best = allowed.first;
  double bestGap = (value - best).abs();
  for (final double a in allowed) {
    final double gap = (value - a).abs();
    if (gap < bestGap) {
      best = a;
      bestGap = gap;
    }
  }
  return best;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
