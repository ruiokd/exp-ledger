/// `badge` 读写。
///
/// 只记"发生过"，没有排行榜、没有连续天数威胁、没有"即将失去"。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:sqflite/sqflite.dart';

class BadgeDao {
  const BadgeDao();

  static const String table = Tables.badge;

  /// 同 [code] 只授一次（先到先得，不重复发）。
  Future<bool> award(DatabaseExecutor db, Badge b) async {
    final existing = await db.query(
      table,
      columns: <String>['id'],
      where: 'code = ?',
      whereArgs: <Object?>[b.code],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await db.insert(
      table,
      toRow(b),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  Future<List<Badge>> all(DatabaseExecutor db) async {
    final rows = await db.query(table, orderBy: 'earned_at DESC');
    return rows.map(fromRow).toList();
  }

  Future<bool> has(DatabaseExecutor db, String code) async {
    final rows = await db.query(
      table,
      columns: <String>['id'],
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Map<String, Object?> toRow(Badge b) => <String, Object?>{
        'id': b.id,
        'code': b.code,
        'title': b.title,
        'detail': b.detail,
        'day_key': b.dayKey?.iso,
        'earned_at': b.earnedAt.toIso8601String(),
      };

  Badge fromRow(Map<String, Object?> r) {
    final dayRaw = r['day_key'];
    return Badge(
      id: r['id']?.toString() ?? '',
      code: r['code']?.toString() ?? '',
      title: r['title']?.toString() ?? '',
      detail: r['detail']?.toString() ?? '',
      dayKey: dayRaw == null ? null : DayKey.parse(dayRaw.toString()),
      earnedAt: parseDate(r['earned_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
