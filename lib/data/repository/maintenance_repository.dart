/// 维护：导出、清空、行数统计。
///
/// 数据全本地，所以"导出"就是把所有表原样倒成 JSON——
/// 不加密、不脱敏、不上传。用户拿走的是一份能自己读的文件。
library;

import 'dart:convert';

import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/migrations.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class MaintenanceRepository {
  MaintenanceRepository({required AppDatabase database})
      : _app = database,
        _db = database.db;

  final AppDatabase _app;
  final Database _db;

  /// 全量导出。表名来自白名单 [Tables.all]，不接受外部传入——
  /// 避免把表名拼进 SQL 时被打穿。
  Future<Map<String, Object?>> exportAll() async {
    final tables = <String, Object?>{};
    for (final table in Tables.all) {
      tables[table] = await _db.rawQuery('SELECT * FROM $table');
    }
    return <String, Object?>{
      'app': 'exp_ledger',
      'schema_version': Migrations.version,
      'exported_at': nowIso(),
      'tables': tables,
    };
  }

  Future<String> exportJson({bool pretty = false}) async {
    final data = await exportAll();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(data)
        : jsonEncode(data);
  }

  /// 每张表的行数。设置页的"数据概况"用它。
  Future<Map<String, int>> rowCounts() async {
    final out = <String, int>{};
    for (final table in Tables.all) {
      final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      out[table] = asInt(rows.first['c']);
    }
    return out;
  }

  /// 清空全部数据（保留 schema 与默认档案）。不可撤销。
  Future<void> wipeAll() => _app.wipeAll();

  /// 只清某一年的记录。用户换手机、想从今年重新开始时用。
  Future<int> deleteYear(int year) async {
    final from = '$year-01-01';
    final to = '$year-12-31';
    var removed = 0;
    await _db.transaction((Transaction txn) async {
      removed += await txn.delete(
        Tables.dailyLog,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      await txn.delete(
        Tables.valenceEvent,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      await txn.delete(
        Tables.negativeEvent,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      await txn.delete(
        Tables.daySettlement,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      await txn.delete(
        Tables.abilitySnapshot,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      await txn.delete(
        Tables.forecastPoint,
        where: 'day_key >= ? AND day_key <= ?',
        whereArgs: <Object?>[from, to],
      );
      // 删完把这一年标脏，下次启动会从最早那天重算。
      await txn.insert(
        Tables.dirtyDay,
        <String, Object?>{'day_key': from, 'reason': 'delete_year', 'marked_at': nowIso()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return removed;
  }
}
