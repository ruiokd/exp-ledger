import 'package:exp_ledger/core/util/date_key.dart';

/// 能量账本日视图（六层账本的第 1–3 层）。
class EnergyLedger {
  const EnergyLedger({
    required this.day,
    required this.intakeKcal,
    required this.bmr,
    required this.tef,
    required this.exercise,
    required this.epoc,
    required this.neat,
    this.trainingEfficiency = 0,
    this.timeEfficiency = 0,
    this.balanceLow = 0,
    this.balanceHigh = 0,
  });

  final DayKey day;

  /// 1. 摄入
  final double intakeKcal;

  /// 2. 消耗拆解
  final double bmr;
  final double tef;
  final double exercise;
  final double epoc;
  final double neat;

  double get expenditure => bmr + tef + exercise + epoc + neat;

  /// 3. 有效率
  /// 训练效率 = 有效训练量 / 总消耗（单位重量负荷每千卡，归一到 0–1 的展示值）。
  final double trainingEfficiency;

  /// 时间效率 = 有效练习时长 / 总投入时长。
  final double timeEfficiency;

  /// 摄入-消耗平衡给区间而不是单点。
  final double balanceLow;
  final double balanceHigh;

  bool get isDeficit => balanceHigh < 0;

  bool get isSurplus => balanceLow > 0;

  /// 区间跨过零点 = 数据精度不足以判断盈余或缺口。
  bool get isInconclusive => balanceLow <= 0 && balanceHigh >= 0;

  String get balanceLabel {
    if (isInconclusive) return '在误差范围内平衡';
    return isDeficit ? '缺口' : '盈余';
  }

  Map<String, Object?> toRow() => {
        'day_key': day.iso,
        'intake_kcal': intakeKcal,
        'bmr': bmr,
        'tef': tef,
        'exercise': exercise,
        'epoc': epoc,
        'neat': neat,
        'expenditure': expenditure,
        'training_efficiency': trainingEfficiency,
        'time_efficiency': timeEfficiency,
        'balance_low': balanceLow,
        'balance_high': balanceHigh,
      };
}
