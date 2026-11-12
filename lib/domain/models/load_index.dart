import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/domain/enums.dart';

/// ACWR 区间。用于 UI 配色与文案，判定逻辑在 science/acwr.dart。
enum AcwrBand {
  underTrained('偏低：可能正在失去适应'),
  low('低风险区间'),
  warning('警戒：负荷爬升偏快'),
  high('高风险：建议降载并考虑就医评估');

  const AcwrBand(this.label);

  final String label;

  bool get isRisk => this == AcwrBand.warning || this == AcwrBand.high;
}

/// 某一日的负荷与状态快照。
///
/// 注意 sRPE / ACWR 都源自竞技体育研究，用于普通人群是外推近似，
/// **只作提示不作诊断**——这句话必须随每次展示一起出现。
class LoadIndex {
  const LoadIndex({
    required this.day,
    this.srpeToday = 0,
    this.acute7 = 0,
    this.chronic28 = 0,
    this.acwr,
    this.damageLoad = 0,
    this.sleepDebtHours = 0,
    this.consecutiveHighDays = 0,
  });

  final DayKey day;

  /// 当日 session-RPE 内负荷（RPE × 分钟）。
  final double srpeToday;

  /// 近 7 天平均负荷。
  final double acute7;

  /// 近 28 天平均负荷。
  final double chronic28;

  /// 急性/慢性比值。慢速为 0 时无定义，返回 null。
  final double? acwr;

  final double damageLoad;
  final double sleepDebtHours;
  final int consecutiveHighDays;

  static LoadIndex empty(DayKey day) => LoadIndex(day: day);

  AcwrBand get band {
    final v = acwr;
    if (v == null) return AcwrBand.low;
    if (v < 0.8) return AcwrBand.underTrained;
    if (v <= 1.3) return AcwrBand.low;
    if (v <= 1.5) return AcwrBand.warning;
    return AcwrBand.high;
  }

  LoadIndex copyWith({
    DayKey? day,
    double? srpeToday,
    double? acute7,
    double? chronic28,
    double? acwr,
    double? damageLoad,
    double? sleepDebtHours,
    int? consecutiveHighDays,
  }) {
    return LoadIndex(
      day: day ?? this.day,
      srpeToday: srpeToday ?? this.srpeToday,
      acute7: acute7 ?? this.acute7,
      chronic28: chronic28 ?? this.chronic28,
      acwr: acwr ?? this.acwr,
      damageLoad: damageLoad ?? this.damageLoad,
      sleepDebtHours: sleepDebtHours ?? this.sleepDebtHours,
      consecutiveHighDays: consecutiveHighDays ?? this.consecutiveHighDays,
    );
  }

  LoadIndex sanitized() => LoadIndex(
        day: day,
        srpeToday: srpeToday.clampRange(0, 10000),
        acute7: acute7.clampRange(0, 10000),
        chronic28: chronic28.clampRange(0, 10000),
        acwr: acwr?.clampRange(0, 5),
        damageLoad: damageLoad.clampRange(0, 100),
        sleepDebtHours: sleepDebtHours.clampRange(0, 72),
        consecutiveHighDays: consecutiveHighDays,
      );

  Map<String, Object?> toRow() => {
        'day_key': day.iso,
        'srpe_today': srpeToday,
        'acute_7': acute7,
        'chronic_28': chronic28,
        'acwr': acwr,
        'band': band.name,
        'damage_load': damageLoad,
        'sleep_debt_hours': sleepDebtHours,
        'consecutive_high_days': consecutiveHighDays,
      };
}

/// 能力快照：五维雷达 + 总经验 + 等级。
class AbilitySnapshot {
  const AbilitySnapshot({
    required this.day,
    required this.abilities,
    required this.completeness,
    required this.totalExp,
    required this.level,
    required this.buffer,
    this.status = SettlementStatus.settled,
  });

  final DayKey day;

  /// 五维能力值（0–100 的长期趋势值，不是当日分）。
  final Map<String, double> abilities;

  /// 每一维的数据完整度 0–1，雷达图用它做透明度。
  final Map<String, double> completeness;

  final double totalExp;
  final int level;

  /// 缓冲池：负向经验优先从这里扣，扣完才掉等级。
  final double buffer;

  final SettlementStatus status;

  double abilityOf(String axis) => abilities[axis] ?? 0;

  double completenessOf(String axis) => completeness[axis] ?? 0;

  Map<String, Object?> toRow() => {
        'day_key': day.iso,
        'abilities': abilities,
        'completeness': completeness,
        'total_exp': totalExp,
        'level': level,
        'buffer': buffer,
        'status': status.name,
      };
}
