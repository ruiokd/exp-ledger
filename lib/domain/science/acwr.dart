/// 负荷风险监控：ACWR（Acute:Chronic Workload Ratio）。
///
/// 出处：Gabbett, 2016, British Journal of Sports Medicine 提出的
/// "急性:慢性负荷比"。**必须同时标注的三件事**：
///   1. 该指标源自竞技体育研究，普通人群使用属外推近似；
///   2. Impellizzeri et al., 2020 指出其数学耦合（分子含于分母）
///      会带来统计假象，因此只能作趋势提示，不能作诊断；
///   3. 它不预测伤病，只提示"负荷爬升是否过陡"。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/models/load_index.dart';

/// 一次 ACWR 计算的结果。
class AcwrResult {
  const AcwrResult({
    required this.acute7,
    required this.chronic28,
    required this.ratio,
    required this.band,
    required this.daysWithData,
  });

  final double acute7;
  final double chronic28;

  /// 慢性负荷为 0 时无定义（null），UI 应显示"数据还不够"而不是 0。
  final double? ratio;

  final AcwrBand band;
  final int daysWithData;

  bool get isDefined => ratio != null;

  /// 数据不足 14 天时，ACWR 不稳，只作参考。
  bool get isProvisional => daysWithData < 14;
}

/// 计算某一日的 ACWR。
///
/// 急性 = 近 7 天（含当日）日均负荷；慢性 = 近 28 天（含当日）日均负荷。
/// 缺失的日子按 0 计（不是跳过），否则"停练一周"会被算成没变化。
AcwrResult computeAcwr({
  required Map<DayKey, double> dailyLoads,
  required DayKey today,
  BalanceConfig? cfg,
}) {
  final c = cfg ?? kDefaultConfig;
  var sum7 = 0.0;
  var sum28 = 0.0;
  var daysWithData = 0;
  for (var i = 0; i < 28; i++) {
    final day = today.addDays(-i);
    final load = dailyLoads[day] ?? 0;
    if (load > 0) daysWithData++;
    sum28 += load;
    if (i < 7) sum7 += load;
  }
  final acute = sum7 / 7;
  final chronic = sum28 / 28;
  final ratio = chronic <= 0 ? null : acute / chronic;
  return AcwrResult(
    acute7: acute,
    chronic28: chronic,
    ratio: ratio,
    band: bandFor(ratio, c),
    daysWithData: daysWithData,
  );
}

/// 区间判定。用配置里的阈值，数值实验室改完立刻生效。
AcwrBand bandFor(double? ratio, [BalanceConfig? cfg]) {
  final c = cfg ?? kDefaultConfig;
  if (ratio == null) return AcwrBand.low;
  if (ratio < c.acwrLowRiskMin) return AcwrBand.underTrained;
  if (ratio <= c.acwrLowRiskMax) return AcwrBand.low;
  if (ratio <= c.acwrWarningMax) return AcwrBand.warning;
  return AcwrBand.high;
}

/// 把 ACWR 结果合成到 LoadIndex。
LoadIndex mergeAcwrInto(LoadIndex base, AcwrResult result) => base.copyWith(
      acute7: result.acute7,
      chronic28: result.chronic28,
      acwr: result.ratio,
    );

/// 中性提示文案。禁止"过度训练警告！"这种写法。
/// 高风险时**必须**附带就医建议，且 App 不下诊断。
String acwrAdvice(AcwrResult r) {
  if (!r.isDefined) return '负荷数据还不够，先把每天的训练记上两三天。';
  switch (r.band) {
    case AcwrBand.underTrained:
      return '近期负荷偏低，身体可能正在退出适应（去训练效应）。不用急，慢慢把量加回来。';
    case AcwrBand.low:
      return '负荷爬升在低风险区间（0.8–1.3），这个节奏可以保持。';
    case AcwrBand.warning:
      return '负荷爬升偏快（1.3–1.5）。接下来几天建议把强度压一档，让恢复跟上。';
    case AcwrBand.high:
      return '负荷比已超过 1.5。建议立即降载，并留意关节疼痛、持续疲劳、睡眠变差等信号。'
          '若出现明显疼痛、心悸或异常乏力，请就医评估——本 App 不做诊断。';
  }
}

/// 数据不足时的置信折扣：14 天以下给 0.5，21 天以上给 1.0。
double acwrConfidence(int daysWithData) =>
    (daysWithData / 21.0).clampRange(0.5, 1.0);
