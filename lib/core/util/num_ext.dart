import 'dart:math' as math;

/// 数值工具。所有生理量在进入 UI 前都必须经过 clamp，避免脏数据画出离谱曲线。
extension NumExt on num {
  double clampRange(double lo, double hi) =>
      this < lo ? lo : (this > hi ? hi : toDouble());

  double get asDouble => toDouble();

  /// 保留 [digits] 位小数（不引入 intl）。
  double roundTo(int digits) {
    final f = math.pow(10, digits).toDouble();
    return (this * f).roundToDouble() / f;
  }

  String fmt([int digits = 0]) => roundTo(digits).toStringAsFixed(digits);

  bool get isFiniteNum => isFinite;
}

double clamp01(double v) => v.clampRange(0, 1);

/// 安全幂：负底数、NaN 一律返回 0，保证曲线函数在脏输入下不抛异常。
double powSafe(double base, double exp) {
  if (base.isNaN || base <= 0) return 0;
  final r = math.pow(base, exp).toDouble();
  return r.isFinite ? r : 0;
}

double lerp(double a, double b, double t) => a + (b - a) * t;

/// 加权平均，权重求和为 0 时退化为简单平均。
double weightedMean(List<double> values, List<double> weights) {
  assert(values.length == weights.length);
  var sw = 0.0;
  var sv = 0.0;
  for (var i = 0; i < values.length; i++) {
    sw += weights[i];
    sv += values[i] * weights[i];
  }
  if (sw <= 0) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
  return sv / sw;
}

/// 逻辑斯蒂映射，用于"强度线索 → 系数"这类平滑过渡。
double logistic(double x, {double steepness = 6, double mid = 0.5}) =>
    1 / (1 + math.exp(-steepness * (x - mid)));

/// 峰谷噪声：给定日期与倍数，返回 [-1, 1]，用于把估算区间画得有呼吸感。
/// 使用确定性哈希，保证同一日期每次渲染一致（可重放）。
double deterministicNoise(int seed, {int mod = 1000}) {
  var x = seed * 7919 + 104729;
  x = (x ^ (x >> 13)) * 1274126177;
  x = x & 0x7fffffff;
  return ((x % (mod * 2)) / mod) - 1;
}
