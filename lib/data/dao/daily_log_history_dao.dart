/// `daily_log_history`：修订链。
///
/// 每次覆盖同一幂等键，旧版本先整行 JSON 归档到这里，再写新行。
/// 这样"我改过什么"永远可查，且 grade 重算可以追溯输入变化。
library;

import 'dart:convert';

import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class DailyLogHistoryDao {
  const DailyLogHistoryDao();

  static const String table = Tables.dailyLogHistory;

  /// 归档一条旧行。[row] 是 `daily_log` 的完整列 map。
  ///
  /// 用 INSERT OR IGNORE：同一次修订被重复归档不报错、不产生重复。
  Future<int> archive(DatabaseExecutor db, Map<String, Object?> row) {
    return db.insert(
      table,
      <String, Object?>{
        'idempotency_key': row['idempotency_key'],
        'revision': asInt(row['revision']),
        'day_key': row['day_key'],
        'row_json': jsonEncode(row),
        'superseded_at': nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 某个幂等键的全部历史版本（旧 → 新）。
  Future<List<Map<String, Object?>>> versionsOf(
    DatabaseExecutor db,
    String idempotencyKey,
  ) async {
    final rows = await db.query(
      table,
      where: 'idempotency_key = ?',
      whereArgs: <Object?>[idempotencyKey],
      orderBy: 'revision ASC',
    );
    return rows
        .map<Map<String, Object?>>(
          (Map<String, Object?> r) =>
              decodeMap(r['row_json']?.toString())..['_superseded_at'] = r['superseded_at'],
        )
        .toList();
  }

  Future<List<Map<String, Object?>>> recent(
    DatabaseExecutor db, {
    int limit = 50,
  }) {
    return db.query(
      table,
      orderBy: 'superseded_at DESC',
      limit: limit,
    );
  }

  Future<int> countAll(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return asInt(rows.first['c']);
  }
}
