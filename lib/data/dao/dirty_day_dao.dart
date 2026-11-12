/// `dirty_day`：脏日队列。
///
/// 写入只做一件事——把那天标脏。真正重算交给
/// [SettlementRepository]，从最早的脏日一路跑到今天。
///
/// 为什么落库而不是放内存：进程被系统杀掉很常见，
/// 重算任务不能因此丢；下次启动 `recomputePending()` 接着跑。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class DirtyDayDao {
  const DirtyDayDao();

  static const String table = Tables.dirtyDay;

  /// 标脏。同一天重复标不叠加（主键覆盖），[reason] 保留最后一次。
  Future<void> mark(
    DatabaseExecutor db,
    DayKey day, {
    String reason = 'write',
  }) async {
    await db.insert(
      table,
      <String, Object?>{
        'day_key': day.iso,
        'reason': reason,
        'marked_at': nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 最早一条脏日。没有则返回 null。
  Future<DayKey?> earliest(DatabaseExecutor db) async {
    final rows = await db.query(
      table,
      columns: <String>['day_key'],
      orderBy: 'day_key ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DayKey.parse(rows.first['day_key'].toString());
  }

  Future<List<DayKey>> all(DatabaseExecutor db) async {
    final rows = await db.query(
      table,
      columns: <String>['day_key'],
      orderBy: 'day_key ASC',
    );
    return rows
        .map<DayKey>((Map<String, Object?> r) => DayKey.parse(r['day_key'].toString()))
        .toList();
  }

  /// 重算到 [through] 之后，清掉这之前的标记。
  Future<int> clearThrough(DatabaseExecutor db, DayKey through) => db.delete(
        table,
        where: 'day_key <= ?',
        whereArgs: <Object?>[through.iso],
      );

  Future<int> clearAll(DatabaseExecutor db) => db.delete(table);

  Future<int> count(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return asInt(rows.first['c']);
  }
}
