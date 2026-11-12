/// 结算仓储：把原始记录变成曲线上的一个点，并且支持**历史修正后重跑**。
///
/// 核心是两件事：
///   1. `recomputeFrom(day)`：从某天重跑到今天。因为
///      [SettlementPipeline.settle] 是纯函数，重跑必然收敛到同一结果。
///   2. 每一天都把 `state_after` 落进 `day_settlement`，
///      于是"今天的状态"不需要在内存里背着整条历史。
///
/// 顺序（不能交换）：
///   删当日旧产物 → 算负荷 → 算结算 → 写正向/负向 → 写结算 → 写快照 → 写预测
library;

import 'dart:async';

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/ability_snapshot_dao.dart';
import 'package:exp_ledger/data/dao/config_dao.dart';
import 'package:exp_ledger/data/dao/daily_log_dao.dart';
import 'package:exp_ledger/data/dao/day_settlement_dao.dart';
import 'package:exp_ledger/data/dao/dirty_day_dao.dart';
import 'package:exp_ledger/data/dao/forecast_point_dao.dart';
import 'package:exp_ledger/data/dao/load_index_dao.dart';
import 'package:exp_ledger/data/dao/negative_event_dao.dart';
import 'package:exp_ledger/data/dao/valence_event_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/snapshot/snapshot_builder.dart';
import 'package:exp_ledger/domain/engine/level_curve.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/science/acwr.dart';
import 'package:exp_ledger/domain/science/s_rpe.dart';
import 'package:exp_ledger/domain/settlement/settlement_pipeline.dart';
import 'package:sqflite/sqflite.dart';

/// 一次重算的结果。
class SettlementRun {
  const SettlementRun({
    this.from,
    this.through,
    this.days = const <DayKey>[],
    this.wasClamped = false,
  });

  static const SettlementRun none = SettlementRun();

  final DayKey? from;
  final DayKey? through;

  /// 实际重算过的日期（升序）。
  final List<DayKey> days;

  /// 起点被上移过（历史太长，只重算最近 400 天）。
  final bool wasClamped;

  bool get isEmpty => days.isEmpty;

  int get count => days.length;

  @override
  String toString() => isEmpty
      ? 'SettlementRun(空)'
      : 'SettlementRun(${from?.iso} → ${through?.iso}, ${days.length} 天)';
}

/// 重算最多回溯多少天。再往前属于"考古"，一次性慢查询不如不做。
const int kMaxRecomputeDays = 400;

class SettlementRepository {
  SettlementRepository({required AppDatabase database, DateTime Function()? clock})
      : _db = database.db,
        _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  final SettlementPipeline _pipeline = const SettlementPipeline();
  final SnapshotBuilder _builder = const SnapshotBuilder();

  final DailyLogDao _daily = const DailyLogDao();
  final DirtyDayDao _dirty = const DirtyDayDao();
  final ValenceEventDao _valence = const ValenceEventDao();
  final NegativeEventDao _negatives = const NegativeEventDao();
  final DaySettlementDao _settlements = const DaySettlementDao();
  final AbilitySnapshotDao _snapshots = const AbilitySnapshotDao();
  final ForecastPointDao _forecast = const ForecastPointDao();
  final LoadIndexDao _loads = const LoadIndexDao();
  final ConfigDao _config = const ConfigDao();

  /// 串行锁：两次重算并发跑会互相删对方的产物。
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  DayKey get today => DayKey.today(_clock());

  /// 从最早的脏日开始重算。启动时调一次就够了。
  Future<SettlementRun> recomputePending({DayKey? through}) {
    return _serialized(() async {
      final earliest = await _dirty.earliest(_db);
      if (earliest == null) return SettlementRun.none;
      return _run(earliest, through ?? today);
    });
  }

  /// 从指定日重算到今天（含）。历史修正、撤销、改配置都走这里。
  Future<SettlementRun> recomputeFrom(DayKey from, {DayKey? through}) {
    return _serialized(() => _run(from, through ?? today));
  }

  Future<SettlementRun> _run(DayKey from, DayKey through) async {
    if (through.isBefore(from)) return SettlementRun.none;

    var start = from;
    var clamped = false;
    final span = through.diffDays(from);
    if (span > kMaxRecomputeDays) {
      start = through.addDays(-kMaxRecomputeDays);
      clamped = true;
    }

    final config = await _config.effective(_db);
    final recomputed = <DayKey>[];

    await _db.transaction((Transaction txn) async {
      // ---- 0. 清掉起点之后的产物（raw 记录与修订历史不动）----
      // 必须先删负向事件：否则 existingRootKeys 会把自己上一轮的结果
      // 当成"历史已经扣过"，重算就不收敛了。
      await _valence.deleteFrom(txn, start);
      await _negatives.deleteFrom(txn, start);

      // 结算行的 revision = 这一天被重算过多少次。删除前先读一遍，
      // 否则每轮都从 1 重新数，这个字段就没有信息量了。
      final revisions = <String, int>{};
      final existingRows = await txn.query(
        Tables.daySettlement,
        columns: <String>['day_key', 'revision'],
        where: 'day_key >= ?',
        whereArgs: <Object?>[start.iso],
      );
      for (final row in existingRows) {
        revisions[row['day_key'].toString()] = asInt(row['revision']);
      }

      await _settlements.deleteFrom(txn, start);
      await _snapshots.deleteFrom(txn, start);
      await _forecast.deleteFrom(txn, start);

      // ---- 1. 恢复起点之前的连续状态 ----
      var state = await _settlements.stateBeforeOf(txn, start);
      var previousSnapshot = await _snapshots.latestBefore(txn, start);

      // ---- 1.5 预取重算窗口的原始记录 ----
      // 日负荷（sRPE/ACWR）与完整度都在内存里算，避免每天再查一次
      // 28 天窗口——401 天 × 28 次查询会把启动拖到十几秒。
      final warmupStart = start.addDays(-28);
      final warmup = await _daily.between(txn, warmupStart, through);
      final index = _HistoryIndex(warmup, config);

      // ---- 2. 逐日推进 ----
      var cursor = start;
      while (!cursor.isAfter(through)) {
        final outcome = await _settleDay(
          txn,
          cursor,
          stateBefore: state,
          previousSnapshot: previousSnapshot,
          config: config,
          index: index,
          revision: (revisions[cursor.iso] ?? 0) + 1,
          isLatest: cursor == through,
        );
        state = outcome.settlement.stateAfter;
        previousSnapshot = outcome.snapshot;
        recomputed.add(cursor);
        cursor = cursor.addDays(1);
      }
    });

    await _dirty.clearThrough(_db, through);
    return SettlementRun(
      from: start,
      through: through,
      days: recomputed,
      wasClamped: clamped,
    );
  }

  Future<_DayOutcome> _settleDay(
    DatabaseExecutor txn,
    DayKey day, {
    required StateVars stateBefore,
    required AbilitySnapshot? previousSnapshot,
    required BalanceConfig config,
    required _HistoryIndex index,
    required int revision,
    required bool isLatest,
  }) async {
    // ---- 输入 ----
    final drafts = await _daily.byDay(txn, day);
    final previousLoad = await _loads.findByDay(txn, day.addDays(-1));
    final load = _loadFor(index, day, config: config, previous: previousLoad);
    final band = bandFor(load.acwr, config);
    final existingRoots = await _negatives.existingRootKeys(txn, day);

    final levelBefore = LevelState(
      level: previousSnapshot?.level ?? 0,
      totalExp: previousSnapshot?.totalExp ?? 0,
      buffer: previousSnapshot?.buffer ?? 0,
    );

    // ---- 结算 ----
    final settlement = _pipeline.settle(
      SettlementInput(
        dayKey: day,
        drafts: drafts,
        stateBefore: stateBefore,
        levelBefore: levelBefore,
        load: load,
        config: config,
        nextBand: band,
        baselineEfficiency: 0,
        existingRootKeys: existingRoots,
        hoursSinceSameMuscle: await _hoursSinceSameMuscle(txn, day),
        // 疲劳用"负荷爬升是否过陡"判定，而不是拿睡债硬猜：
        // ACWR 落在警戒区时，状态乘数本来就该打折。
        fatigued: band.isRisk,
        consecutiveHighIntensityDays: previousLoad?.consecutiveHighDays ?? 0,
      ),
    );

    // ---- 写产物（顺序固定）----
    await _valence.replaceDay(txn, day, settlement.positives);
    await _negatives.replaceDay(txn, day, settlement.negatives);
    await _settlements.save(txn, settlement, revision: revision);

    final daysWithData =
        index.daysWithDataPerAxis(day, config.completenessWindowDays.toInt());
    final snapshot = _builder.build(
      day: day,
      settlement: settlement,
      previous: previousSnapshot,
      daysWithData: daysWithData,
      config: config,
    );
    await _snapshots.save(txn, snapshot);

    final recentDailyExp = await _settlements.averageNetExp(txn, day, 28);
    final forecastMap = isLatest
        ? _builder.buildForecast(
            today: day,
            snapshot: snapshot,
            settlement: settlement,
            recentDailyExp: recentDailyExp,
            config: config,
          )
        : _builder.actualOnly(snapshot);
    await _forecast.replaceForDay(txn, day, forecastMap);

    // 负荷索引回写：把结算后的状态变量留在这一行，下次读历史不用重算。
    final streak = band.isRisk ? (previousLoad?.consecutiveHighDays ?? 0) + 1 : 0;
    await _loads.save(
      txn,
      LoadIndex(
        day: day,
        srpeToday: load.srpeToday,
        acute7: load.acute7,
        chronic28: load.chronic28,
        acwr: load.acwr,
        damageLoad: settlement.stateAfter.damageLoad,
        sleepDebtHours: settlement.stateAfter.sleepDebtHours,
        consecutiveHighDays: streak,
      ).sanitized(),
    );

    return _DayOutcome(settlement, snapshot);
  }

  /// 当日负荷：从记录里的时长与 RPE（缺省用 RIR 反推，再缺省用配置值）算 sRPE，
  /// 再对近 28 天做 ACWR。
  ///
  /// 数据在 [_HistoryIndex] 里预取过一次，这里不再查库——
  /// 401 天 × 28 天窗口逐日查询会把启动拖到十几秒。
  LoadIndex _loadFor(
    _HistoryIndex index,
    DayKey day, {
    required BalanceConfig config,
    required LoadIndex? previous,
  }) {
    final perDay = <DayKey, double>{};
    for (var i = 0; i < 28; i++) {
      final d = day.addDays(-i);
      perDay[d] = index.srpeOn(d);
    }

    final acwr = computeAcwr(dailyLoads: perDay, today: day, cfg: config);
    return LoadIndex(
      day: day,
      srpeToday: index.srpeOn(day),
      acute7: acwr.acute7,
      chronic28: acwr.chronic28,
      acwr: acwr.ratio,
      damageLoad: previous?.damageLoad ?? 0,
      sleepDebtHours: previous?.sleepDebtHours ?? 0,
      consecutiveHighDays: previous?.consecutiveHighDays ?? 0,
    ).sanitized();
  }

  /// 距上次同肌群训练多少小时。没有记录时给一个"很久了"的大数，
  /// 让恢复间隔判定直接放行，而不是把它当成刚练过。
  Future<int> _hoursSinceSameMuscle(DatabaseExecutor txn, DayKey day) async {
    final rows = await txn.query(
      Tables.dailyLog,
      columns: <String>['day_key'],
      where: "behavior_code LIKE ? AND day_key < ?",
      whereArgs: <Object?>['%strength%', day.iso],
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 999;
    final previous = DayKey.parse(rows.first['day_key'].toString());
    return day.diffDays(previous) * 24;
  }

  // ------------------------------------------------------------- 读接口

  Future<DaySettlement?> settlementOf(DayKey day) async {
    final positives = await _valence.byDay(_db, day);
    final negatives = await _negatives.byDay(_db, day);
    return _settlements.find(
      _db,
      day,
      positives: positives,
      negatives: negatives,
    );
  }

  Future<AbilitySnapshot?> snapshotOf(DayKey day) => _snapshots.findByDay(_db, day);

  /// 一段日期内的五维快照。曲线页一次取完，避免按天查 365 次。
  Future<List<AbilitySnapshot>> snapshotSeries(DayKey from, DayKey to) =>
      _snapshots.range(_db, from, to);

  Future<AbilitySnapshot?> latestSnapshot() => _snapshots.latest(_db);

  Future<List<DaySettlement>> series(DayKey from, DayKey to) =>
      _settlements.range(_db, from, to);

  Future<Map<ProjectAxis, List<ForecastPoint>>> forecastOf(DayKey generatedOn) =>
      _forecast.forDay(_db, generatedOn);

  Future<List<ForecastPoint>> actualSeries(
    ProjectAxis axis,
    DayKey from,
    DayKey to,
  ) =>
      _forecast.actualSeries(_db, axis, from, to);

  Future<LoadIndex> loadOf(DayKey day) => _loads.findOrEmpty(_db, day);

  /// 一段日期内的负荷序列。曲线上的"风险区底色"用它。
  Future<List<LoadIndex>> loadSeries(DayKey from, DayKey to) =>
      _loads.range(_db, from, to);

  Future<int> dirtyCount() => _dirty.count(_db);

  Future<int> awaitIdle() async {
    await _tail;
    return 0;
  }
}

/// 重算窗口内的原始记录索引。
///
/// 一次预取，之后每天的 sRPE 与完整度都是内存查表。
/// 这里只做"聚合"，不做任何判定——阈值与曲线仍在 domain 层。
class _HistoryIndex {
  _HistoryIndex(List<DraftEntry> drafts, BalanceConfig config) {
    for (final d in drafts) {
      final minutes = d.metrics['session_minutes'] ??
          d.metrics['minutes'] ??
          d.metrics['effective_minutes'] ??
          0;
      if (minutes > 0) {
        final explicitRpe = d.metrics['rpe'];
        final rir = d.metrics['rir'];
        final rpe = explicitRpe ??
            (rir != null ? rpeFromRir(rir.round()) : config.srpeDefaultRpe);
        _srpe[d.dayKey] =
            (_srpe[d.dayKey] ?? 0) + srpeLoad(rpe: rpe, minutes: minutes);
      }
      _axes.putIfAbsent(d.dayKey, () => <String>{}).add(d.axis.name);
    }
  }

  final Map<DayKey, double> _srpe = <DayKey, double>{};
  final Map<DayKey, Set<String>> _axes = <DayKey, Set<String>>{};

  double srpeOn(DayKey day) => _srpe[day] ?? 0;

  /// 近 [window] 天每个轴"有记录的天数"。
  Map<String, int> daysWithDataPerAxis(DayKey through, int window) {
    final span = window <= 0 ? 1 : window;
    final from = through.addDays(-(span - 1));
    final counts = <String, int>{};
    for (final entry in _axes.entries) {
      if (entry.key.isBefore(from) || entry.key.isAfter(through)) continue;
      for (final axis in entry.value) {
        counts[axis] = (counts[axis] ?? 0) + 1;
      }
    }
    return counts;
  }
}

class _DayOutcome {
  const _DayOutcome(this.settlement, this.snapshot);

  final DaySettlement settlement;
  final AbilitySnapshot snapshot;
}
