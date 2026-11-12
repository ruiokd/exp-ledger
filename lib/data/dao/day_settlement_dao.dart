/// `day_settlement` 读写。
///
/// 这张表是**级联重算的中间层**：一天一行，存结算汇总与前后状态变量。
/// 重算某天时，前一天的 `state_after` 就是今天的 `state_before`——
/// 所以状态在库里是连续可追的，不需要在内存里持有整条历史。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/state_vars.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';
import 'package:sqflite/sqflite.dart';

class DaySettlementDao {
  const DaySettlementDao();

  static const String table = Tables.daySettlement;

  Future<void> save(
    DatabaseExecutor db,
    DaySettlement s, {
    int revision = 0,
  }) async {
    await db.insert(
      table,
      toRow(s, revision: revision),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// [positives] / [negatives] 由仓储层从事件表查出后传进来；
  /// 只读汇总时留空即可（图表主曲线只用汇总与状态）。
  Future<DaySettlement?> find(
    DatabaseExecutor db,
    DayKey day, {
    List<ValenceEvent> positives = const <ValenceEvent>[],
    List<NegativeEvent> negatives = const <NegativeEvent>[],
  }) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first, positives: positives, negatives: negatives);
  }

  /// 直接取结算后的状态变量。重算时每天都要读一次，只要一列。
  Future<StateVars?> stateAfterOf(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      columns: <String>['state_after_json'],
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return decodeState(rows.first['state_after_json']?.toString());
  }

  /// 最近一条早于 [day] 的结算状态。
  ///
  /// 用"最近一条"而不是"day-1"：中间断更几天不该把负债清零。
  Future<StateVars> stateBeforeOf(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      columns: <String>['state_after_json'],
      where: 'day_key < ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) return StateVars.zero;
    return decodeState(rows.first['state_after_json']?.toString());
  }

  Future<int> revisionOf(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      columns: <String>['revision'],
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return asInt(rows.first['revision']);
  }

  Future<List<DaySettlement>> range(
    DatabaseExecutor db,
    DayKey from,
    DayKey to,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key >= ? AND day_key <= ?',
      whereArgs: <Object?>[from.iso, to.iso],
      orderBy: 'day_key ASC',
    );
    return rows
        .map<DaySettlement>(
          (Map<String, Object?> r) => fromRow(
            r,
            positives: const <ValenceEvent>[],
            negatives: const <NegativeEvent>[],
          ),
        )
        .toList();
  }

  /// 近 [days] 天的净经验均值。预测的"现实速率"用它，不用当日值——
  /// 单日波动太大，用一天推 90 天必然离谱。
  Future<double> averageNetExp(
    DatabaseExecutor db,
    DayKey through,
    int days,
  ) async {
    final from = through.addDays(-(days - 1));
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(AVG(net_exp), 0) AS a, COUNT(*) AS c
      FROM $table
      WHERE day_key >= ? AND day_key <= ?
      ''',
      <Object?>[from.iso, through.iso],
    );
    return asDouble(rows.first['a']);
  }

  /// 最近一天有结算的日期。
  Future<DayKey?> latestDay(DatabaseExecutor db) async {
    final rows = await db.query(
      table,
      columns: <String>['day_key'],
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DayKey.parse(rows.first['day_key'].toString());
  }

  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(DaySettlement s, {int revision = 0}) =>
      <String, Object?>{
        'day_key': s.dayKey.iso,
        'positive_exp': s.positiveExp,
        'negative_exp': s.negativeExp,
        'net_exp': s.netExp,
        'status': s.status.name,
        'state_before_json': encodeJsonMap(s.stateBefore.toMap()),
        'state_after_json': encodeJsonMap(s.stateAfter.toMap()),
        'alert_json': s.alert == null
            ? null
            : encodeJsonMap(<String, Object?>{
                'code': s.alert!.code,
                'title': s.alert!.title,
                'message': s.alert!.message,
                'advice': s.alert!.advice,
                'blocking': boolToInt(s.alert!.blocking),
              }),
        'notes_json': encodeJsonList(s.notes),
        'recovery_json': encodeJsonList(s.recoveryPlan),
        'level_before': s.levelBefore,
        'level_after': s.levelAfter,
        'buffer_after': s.bufferAfter,
        'is_interruption': boolToInt(s.isInterruption),
        'revision': revision,
        'computed_at': nowIso(),
      };

  DaySettlement fromRow(
    Map<String, Object?> r, {
    List<ValenceEvent> positives = const <ValenceEvent>[],
    List<NegativeEvent> negatives = const <NegativeEvent>[],
  }) {
    return DaySettlement(
      dayKey: DayKey.parse(r['day_key'].toString()),
      positives: positives,
      negatives: negatives,
      positiveExp: asDouble(r['positive_exp']),
      negativeExp: asDouble(r['negative_exp']),
      status: parseEnum<SettlementStatus>(
        SettlementStatus.values,
        r['status'],
        SettlementStatus.settled,
      ),
      stateBefore: decodeState(r['state_before_json']?.toString()),
      stateAfter: decodeState(r['state_after_json']?.toString()),
      alert: decodeAlert(r['alert_json']?.toString()),
      notes: decodeStringList(r['notes_json']?.toString()),
      recoveryPlan: decodeStringList(r['recovery_json']?.toString()),
      levelBefore: asInt(r['level_before']),
      levelAfter: asInt(r['level_after']),
      bufferAfter: asDouble(r['buffer_after']),
      isInterruption: asBool(r['is_interruption']),
    );
  }

  StateVars decodeState(String? raw) {
    final m = decodeMap(raw);
    if (m.isEmpty) return StateVars.zero;
    final asOf = m['as_of'];
    return StateVars(
      sleepDebtHours: asDouble(m['sleep_debt_hours']),
      damageLoad: asDouble(m['damage_load']),
      recoveryDebt: asDouble(m['recovery_debt']),
      consistency: asDouble(m['consistency'], fallback: 0.5),
      asOf: asOf == null ? null : DayKey.parse(asOf.toString()),
    ).sanitized();
  }

  SafetyAlert? decodeAlert(String? raw) {
    final m = decodeMap(raw);
    if (m.isEmpty) return null;
    return SafetyAlert(
      code: m['code']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
      advice: m['advice']?.toString() ?? '',
      blocking: asBool(m['blocking'], fallback: true),
    );
  }
}
