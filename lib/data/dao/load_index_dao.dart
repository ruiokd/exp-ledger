/// `load_index` 读写。
///
/// 一天一行负荷快照。ACWR 可能无定义（慢性负荷为 0）——
/// 这时列里存 NULL，读回来是 null，UI 显示"暂不可算"而不是 0。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:sqflite/sqflite.dart';

class LoadIndexDao {
  const LoadIndexDao();

  static const String table = Tables.loadIndex;

  Future<void> save(DatabaseExecutor db, LoadIndex l) async {
    await db.insert(
      table,
      toRow(l),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<LoadIndex?> findByDay(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<LoadIndex> findOrEmpty(DatabaseExecutor db, DayKey day) async =>
      await findByDay(db, day) ?? LoadIndex.empty(day);

  Future<List<LoadIndex>> range(
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

  /// 连续高风险天数：从 [day] 往前数，ACWR 落在警戒/高风险区间的天数。
  /// 用 SQL 数不划算（区间边界在配置里），交给调用方逐日判断。
  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(LoadIndex l) => <String, Object?>{
        'day_key': l.day.iso,
        'srpe_today': l.srpeToday,
        'acute_7': l.acute7,
        'chronic_28': l.chronic28,
        'acwr': l.acwr,
        'band': l.band.name,
        'damage_load': l.damageLoad,
        'sleep_debt_hours': l.sleepDebtHours,
        'consecutive_high_days': l.consecutiveHighDays,
        'updated_at': nowIso(),
      };

  LoadIndex fromRow(Map<String, Object?> r) => LoadIndex(
        day: DayKey.parse(r['day_key'].toString()),
        srpeToday: asDouble(r['srpe_today']),
        acute7: asDouble(r['acute_7']),
        chronic28: asDouble(r['chronic_28']),
        acwr: asDoubleOrNull(r['acwr']),
        damageLoad: asDouble(r['damage_load']),
        sleepDebtHours: asDouble(r['sleep_debt_hours']),
        consecutiveHighDays: asInt(r['consecutive_high_days']),
      );
}
