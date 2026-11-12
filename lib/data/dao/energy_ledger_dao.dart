/// `energy_ledger` 读写。
///
/// 一天一行。摄入热量目前没有采集入口，写库时会是 0 并标"空缺"，
/// 第 5 步加饮食采集后再补——这里不做假数据填充。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/models/energy_ledger.dart';
import 'package:sqflite/sqflite.dart';

class EnergyLedgerDao {
  const EnergyLedgerDao();

  static const String table = Tables.energyLedger;

  Future<void> save(DatabaseExecutor db, EnergyLedger e) async {
    await db.insert(
      table,
      toRow(e),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EnergyLedger?> findByDay(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<List<EnergyLedger>> range(
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
    return rows.map(fromRow).toList();
  }

  Future<double> averageBalance(
    DatabaseExecutor db,
    DayKey through,
    int days,
  ) async {
    final from = through.addDays(-(days - 1));
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(AVG((balance_low + balance_high) / 2.0), 0) AS a
      FROM $table
      WHERE day_key >= ? AND day_key <= ?
      ''',
      <Object?>[from.iso, through.iso],
    );
    return asDouble(rows.first['a']);
  }

  Map<String, Object?> toRow(EnergyLedger e) => <String, Object?>{
        'day_key': e.day.iso,
        'intake_kcal': e.intakeKcal,
        'bmr': e.bmr,
        'tef': e.tef,
        'exercise': e.exercise,
        'epoc': e.epoc,
        'neat': e.neat,
        'expenditure': e.expenditure,
        'training_efficiency': e.trainingEfficiency,
        'time_efficiency': e.timeEfficiency,
        'balance_low': e.balanceLow,
        'balance_high': e.balanceHigh,
        'updated_at': nowIso(),
      };

  EnergyLedger fromRow(Map<String, Object?> r) => EnergyLedger(
        day: DayKey.parse(r['day_key'].toString()),
        intakeKcal: asDouble(r['intake_kcal']),
        bmr: asDouble(r['bmr']),
        tef: asDouble(r['tef']),
        exercise: asDouble(r['exercise']),
        epoc: asDouble(r['epoc']),
        neat: asDouble(r['neat']),
        trainingEfficiency: asDouble(r['training_efficiency']),
        timeEfficiency: asDouble(r['time_efficiency']),
        balanceLow: asDouble(r['balance_low']),
        balanceHigh: asDouble(r['balance_high']),
      );
}
