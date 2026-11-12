/// `ability_snapshot` 读写。
///
/// 一天一行：五维能力值 + 完整度 + 总经验 / 等级 / 缓冲池。
/// 主图的历史曲线读这张表（`horizon` 为 0 的预测点也来自这里）。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:sqflite/sqflite.dart';

class AbilitySnapshotDao {
  const AbilitySnapshotDao();

  static const String table = Tables.abilitySnapshot;

  Future<void> save(DatabaseExecutor db, AbilitySnapshot s) async {
    await db.insert(
      table,
      toRow(s),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AbilitySnapshot?> findByDay(
    DatabaseExecutor db,
    DayKey day,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  /// 最近一条早于 [day] 的快照。断更几天也不会把等级清零。
  Future<AbilitySnapshot?> latestBefore(
    DatabaseExecutor db,
    DayKey day,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key < ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<AbilitySnapshot?> latest(DatabaseExecutor db) async {
    final rows = await db.query(
      table,
      orderBy: 'day_key DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<List<AbilitySnapshot>> range(
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

  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(AbilitySnapshot s) => <String, Object?>{
        'day_key': s.day.iso,
        'abilities_json': encodeJsonMap(
          s.abilities.map<String, Object?>(
            (String k, double v) => MapEntry<String, Object?>(k, v),
          ),
        ),
        'completeness_json': encodeJsonMap(
          s.completeness.map<String, Object?>(
            (String k, double v) => MapEntry<String, Object?>(k, v),
          ),
        ),
        'total_exp': s.totalExp,
        'level': s.level,
        'buffer': s.buffer,
        'status': s.status.name,
        'computed_at': nowIso(),
      };

  AbilitySnapshot fromRow(Map<String, Object?> r) => AbilitySnapshot(
        day: DayKey.parse(r['day_key'].toString()),
        abilities: decodeDoubleMap(r['abilities_json']?.toString()),
        completeness: decodeDoubleMap(r['completeness_json']?.toString()),
        totalExp: asDouble(r['total_exp']),
        level: asInt(r['level']),
        buffer: asDouble(r['buffer']),
        status: parseEnum<SettlementStatus>(
          SettlementStatus.values,
          r['status'],
          SettlementStatus.settled,
        ),
      );
}
