import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';

/// 一天的结算结果。主图、明细页、周报都从这里取数。
class DaySettlement {
  const DaySettlement({
    required this.dayKey,
    required this.positives,
    required this.negatives,
    required this.positiveExp,
    required this.negativeExp,
    required this.status,
    required this.stateBefore,
    required this.stateAfter,
    this.alert,
    this.notes = const [],
    this.recoveryPlan = const [],
    this.levelBefore = 0,
    this.levelAfter = 0,
    this.bufferAfter = 0,
    this.isInterruption = false,
  });

  final DayKey dayKey;
  final List<ValenceEvent> positives;
  final List<NegativeEvent> negatives;

  final double positiveExp;
  final double negativeExp;

  /// 当日净经验（可为负）。暂停结算时为 0。
  double get netExp =>
      status == SettlementStatus.paused ? 0 : positiveExp + negativeExp;

  final SettlementStatus status;
  final StateVars stateBefore;
  final StateVars stateAfter;

  final SafetyAlert? alert;
  final List<String> notes;

  /// 可回补路径：按影响大小排序的中性行动建议。
  final List<String> recoveryPlan;

  final int levelBefore;
  final int levelAfter;
  final double bufferAfter;

  /// 中断期（生病/受伤/加班/旅行）：图表换底色，不算懈怠。
  final bool isInterruption;

  bool get hasNegative => negativeExp < 0;

  int get droppedLevels => levelBefore - levelAfter > 0 ? levelBefore - levelAfter : 0;

  static DaySettlement empty(DayKey day) => DaySettlement(
        dayKey: day,
        positives: const [],
        negatives: const [],
        positiveExp: 0,
        negativeExp: 0,
        status: SettlementStatus.settled,
        stateBefore: StateVars.zero,
        stateAfter: StateVars.zero,
      );
}

/// 预测点。两条线同时存在，用户自己看对照。
class ForecastPoint {
  const ForecastPoint({
    required this.day,
    required this.maintain,
    required this.correct,
    required this.low,
    required this.high,
    required this.confidence,
    this.isProjection = true,
  });

  final DayKey day;

  /// "若维持现状"的预测值（下行）。
  final double maintain;

  /// "若立即修正"的预测值（回升）。
  final double correct;

  /// 维持现状线的置信区间下界。
  final double low;

  /// 维持现状线的置信区间上界。
  final double high;

  /// 0–1，随预测天数衰减。UI 上用它调虚线透明度。
  final double confidence;

  final bool isProjection;

  double get spread => high - low;
}
