/// 数据层的 Riverpod 供应商。
///
/// 规矩：
///   - 只有这里 `new` 仓储。UI 里出现 `SettlementRepository(...)` 就是错的。
///   - 读用 `FutureProvider`，写用仓储方法 + `ref.invalidate(...)`。
///   - 页面里不重算任何数字：要什么，从仓库读。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:exp_ledger/services/export_service.dart';
import 'package:exp_ledger/services/notification_service.dart';
import 'package:exp_ledger/services/widget_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 在 `main()` 里用 `overrideWithValue` 注入。拿不到就说明启动顺序错了。
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('appDatabaseProvider 没有注入：检查 main()'),
);

final Provider<SettlementRepository> settlementRepositoryProvider =
    Provider<SettlementRepository>(
  (ref) => SettlementRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<CaptureRepository> captureRepositoryProvider =
    Provider<CaptureRepository>(
  (ref) => CaptureRepository(
    database: ref.watch(appDatabaseProvider),
    settlement: ref.watch(settlementRepositoryProvider),
  ),
);

final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
  (ref) => ProfileRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<ConfigRepository> configRepositoryProvider =
    Provider<ConfigRepository>(
  (ref) => ConfigRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<MemoryRepository> memoryRepositoryProvider =
    Provider<MemoryRepository>(
  (ref) => MemoryRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<ConfirmationRepository> confirmationRepositoryProvider =
    Provider<ConfirmationRepository>(
  (ref) => ConfirmationRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<SettingRepository> settingRepositoryProvider =
    Provider<SettingRepository>(
  (ref) => SettingRepository(database: ref.watch(appDatabaseProvider)),
);

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final Provider<WidgetBridge> widgetBridgeProvider =
    Provider<WidgetBridge>((ref) => WidgetBridge());

final Provider<ExportService> exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    maintenance: ref.watch(maintenanceRepositoryProvider),
  ),
);

final Provider<MaintenanceRepository> maintenanceRepositoryProvider =
    Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(database: ref.watch(appDatabaseProvider)),
);

// ---------------------------------------------------------------- 首页

/// 首页要的全部数据，一次查完。
///
/// 分开查会让首屏出现"数字先到、图表后到"的跳动；
/// 这里一次性拼好，页面只渲染。
class TodayView {
  const TodayView({
    required this.day,
    required this.settlement,
    required this.snapshot,
    required this.load,
    required this.entries,
    required this.confirmations,
    required this.config,
    required this.pendingReviews,
  });

  final DayKey day;
  final DaySettlement? settlement;
  final AbilitySnapshot? snapshot;
  final LoadIndex load;
  final List<DraftEntry> entries;
  final List<ConfirmationTask> confirmations;
  final BalanceConfig config;
  final int pendingReviews;

  double get netExp => settlement?.netExp ?? 0;

  SettlementStatus get status => settlement?.status ?? SettlementStatus.settled;

  bool get hasRecord => entries.isNotEmpty;

  /// 等级进度 0–1。没有快照时从 0 开始，不假装有进度。
  double get levelProgress {
    final snap = snapshot;
    if (snap == null) return 0;
    final lo = config.levelThreshold(snap.level);
    final hi = config.levelThreshold(snap.level + 1);
    if (hi <= lo) return 0;
    return ((snap.totalExp - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
  }

  double abilityOf(ProjectAxis axis) => snapshot?.abilityOf(axis.name) ?? 0;

  double completenessOf(ProjectAxis axis) =>
      snapshot?.completenessOf(axis.name) ?? 0;
}

final FutureProvider<TodayView> todayProvider = FutureProvider<TodayView>(
  (ref) async {
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final capture = ref.watch(captureRepositoryProvider);
    final configRepo = ref.watch(configRepositoryProvider);
    final confirmations = ref.watch(confirmationRepositoryProvider);
    final memory = ref.watch(memoryRepositoryProvider);

    final day = DayKey.today();
    final results = await Future.wait<Object?>(<Future<Object?>>[
      settlementRepo.settlementOf(day),
      settlementRepo.snapshotOf(day),
      settlementRepo.loadOf(day),
      capture.forDay(day),
      confirmations.due(),
      configRepo.effective(),
      memory.countDue(),
    ]);

    return TodayView(
      day: day,
      settlement: results[0] as DaySettlement?,
      snapshot: results[1] as AbilitySnapshot?,
      load: results[2] as LoadIndex,
      entries: results[3] as List<DraftEntry>,
      confirmations: results[4] as List<ConfirmationTask>,
      config: results[5] as BalanceConfig,
      pendingReviews: results[6] as int,
    );
  },
);

// ---------------------------------------------------------------- 曲线

/// 曲线查询参数。用 record 是为了白拿值相等——Riverpod 的 family
/// 靠 `==` 判断是否需要重查，写个普通 class 反而要手写 ==/hashCode。
typedef ChartQuery = ({DayKey from, DayKey to});

class ChartData {
  const ChartData({
    required this.query,
    required this.snapshots,
    required this.settlements,
    required this.loads,
    required this.forecast,
    required this.config,
  });

  final ChartQuery query;
  final List<AbilitySnapshot> snapshots;
  final List<DaySettlement> settlements;
  final List<LoadIndex> loads;
  final Map<ProjectAxis, List<ForecastPoint>> forecast;

  /// 生效配置。风险区判定要跟数值实验室改过的阈值走，
  /// 不能在展示层另抄一套 0.8 / 1.3 / 1.5。
  final BalanceConfig config;

  bool get isEmpty => snapshots.isEmpty;

  DayKey get today => query.to;
}

final FutureProviderFamily<ChartData, ChartQuery> chartProvider =
    FutureProvider.family<ChartData, ChartQuery>(
  (ref, ChartQuery query) async {
    final settlementRepo = ref.watch(settlementRepositoryProvider);
    final results = await Future.wait<Object?>(<Future<Object?>>[
      settlementRepo.series(query.from, query.to),
      settlementRepo.loadSeries(query.from, query.to),
      settlementRepo.forecastOf(query.to),
      ref.watch(configRepositoryProvider).effective(),
    ]);

    final settlements = results[0] as List<DaySettlement>;
    final loads = results[1] as List<LoadIndex>;
    final forecast = results[2] as Map<ProjectAxis, List<ForecastPoint>>;
    final config = results[3] as BalanceConfig;

    // 快照单独取：DaySettlement 里没有五维能力值。
    // 一次 range 查完，不要按天查——365 天就是 365 次往返。
    final snapshots = await settlementRepo.snapshotSeries(
      query.from,
      query.to,
    );

    return ChartData(
      query: query,
      snapshots: snapshots,
      settlements: settlements,
      loads: loads,
      forecast: forecast,
      config: config,
    );
  },
);

/// 系数对照表：默认值 vs 当前值。数值实验室只要这一项，
/// 不必为了拿它去跑一遍行数统计。
final FutureProvider<Map<String, ({double current, double baseline})>>
    configDiffProvider =
    FutureProvider<Map<String, ({double current, double baseline})>>(
  (ref) => ref.watch(configRepositoryProvider).diff(),
);

// ---------------------------------------------------------------- 明细

final FutureProviderFamily<DaySettlement?, DayKey> dayDetailProvider =
    FutureProvider.family<DaySettlement?, DayKey>(
  (ref, DayKey day) =>
      ref.watch(settlementRepositoryProvider).settlementOf(day),
);

final FutureProviderFamily<List<DraftEntry>, DayKey> dayEntriesProvider =
    FutureProvider.family<List<DraftEntry>, DayKey>(
  (ref, DayKey day) => ref.watch(captureRepositoryProvider).forDay(day),
);

/// 最近 30 天有记录的日子，明细页用来翻页。
final FutureProvider<List<DayKey>> recentDaysProvider =
    FutureProvider<List<DayKey>>((ref) async {
  final capture = ref.watch(captureRepositoryProvider);
  final today = DayKey.today();
  final entries = await capture.between(today.addDays(-29), today);
  final days = <DayKey>{};
  for (final e in entries) {
    days.add(e.dayKey);
  }
  return days.toList()..sort((DayKey a, DayKey b) => b.compareTo(a));
});

// ---------------------------------------------------------------- 提醒

/// 提醒设置。默认 21:30，默认关闭——要用户自己打开。
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

final FutureProvider<ReminderSettings> reminderProvider =
    FutureProvider<ReminderSettings>((ref) async {
  final SettingRepository repo = ref.watch(settingRepositoryProvider);
  return ReminderSettings(
    enabled: await repo.readBool(SettingRepository.reminderEnabled),
    hour: await repo.readInt(SettingRepository.reminderHour, fallback: 21),
    minute: await repo.readInt(SettingRepository.reminderMinute, fallback: 30),
  );
});

// ---------------------------------------------------------------- 设置

class SettingsView {
  const SettingsView({
    required this.profile,
    required this.rowCounts,
    required this.configDiff,
    required this.memoryCount,
    required this.dirtyCount,
  });

  final UserProfile profile;
  final Map<String, int> rowCounts;
  final Map<String, ({double current, double baseline})> configDiff;
  final int memoryCount;
  final int dirtyCount;

  bool get hasOverrides => configDiff.entries.any(
        (MapEntry<String, ({double current, double baseline})> e) =>
            (e.value.current - e.value.baseline).abs() > 1e-9,
      );
}

final FutureProvider<SettingsView> settingsProvider =
    FutureProvider<SettingsView>((ref) async {
  final profileRepo = ref.watch(profileRepositoryProvider);
  final configRepo = ref.watch(configRepositoryProvider);
  final maintenance = ref.watch(maintenanceRepositoryProvider);
  final memory = ref.watch(memoryRepositoryProvider);
  final settlement = ref.watch(settlementRepositoryProvider);

  final results = await Future.wait<Object?>(<Future<Object?>>[
    profileRepo.load(),
    maintenance.rowCounts(),
    configRepo.diff(),
    memory.countAll(),
    settlement.dirtyCount(),
  ]);

  return SettingsView(
    profile: results[0] as UserProfile,
    rowCounts: results[1] as Map<String, int>,
    configDiff:
        results[2] as Map<String, ({double current, double baseline})>,
    memoryCount: results[3] as int,
    dirtyCount: results[4] as int,
  );
});

// ---------------------------------------------------------------- 刻度标定层

/// 判定引擎（纯函数，const 实例）。UI 与仓储共用同一个，避免两套规则。
final Provider<AnchorEngine> anchorEngineProvider =
    Provider<AnchorEngine>((ref) => const AnchorEngine());

final Provider<AnchorRepository> anchorRepositoryProvider =
    Provider<AnchorRepository>(
  (ref) => AnchorRepository(
    database: ref.watch(appDatabaseProvider),
    engine: ref.watch(anchorEngineProvider),
  ),
);

/// 个人刻度卡片。写入后 `ref.invalidate(anchorCardsProvider)` 即可刷新。
final FutureProvider<List<AnchorCard>> anchorCardsProvider =
    FutureProvider<List<AnchorCard>>(
  (ref) => ref.watch(anchorRepositoryProvider).cards(),
);

/// 每条卡片对应的权重裁决（先验 / 已被实测覆盖）。
final FutureProvider<Map<String, WeightResolution>> anchorResolutionsProvider =
    FutureProvider<Map<String, WeightResolution>>(
  (ref) => ref.watch(anchorRepositoryProvider).resolutions(),
);

// ---------------------------------------------------------------- 自建项目

final Provider<CustomBehaviorRepository> customBehaviorRepositoryProvider =
    Provider<CustomBehaviorRepository>(
  (ref) => CustomBehaviorRepository(
    database: ref.watch(appDatabaseProvider),
    engine: ref.watch(anchorEngineProvider),
  ),
);

final FutureProvider<List<CustomBehaviorRecord>> customBehaviorsProvider =
    FutureProvider<List<CustomBehaviorRecord>>(
  (ref) => ref.watch(customBehaviorRepositoryProvider).list(),
);
