/// `confirmation_task` 读写。
///
/// 确认闭环：系统不替用户判断"这件事真的发生了"，只把问题排好队，
/// 用户点一下才算数。任务状态只有四种：open / done / skipped / expired。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:sqflite/sqflite.dart';

class ConfirmationDao {
  const ConfirmationDao();

  static const String table = Tables.confirmationTask;

  Future<void> save(DatabaseExecutor db, ConfirmationTask t) async {
    await db.insert(
      table,
      toRow(t),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ConfirmationTask?> byId(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  /// 所有还开着的任务，按到期时间排。
  Future<List<ConfirmationTask>> open(
    DatabaseExecutor db, {
    DayKey? day,
  }) async {
    final where = StringBuffer("status = 'open'");
    final args = <Object?>[];
    if (day != null) {
      where.write(' AND (day_key IS NULL OR day_key <= ?)');
      args.add(day.iso);
    }
    final rows = await db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'COALESCE(due_at, created_at) ASC',
    );
    return rows.map(fromRow).toList();
  }

  /// 到期且还开着的任务（含没有到期时间但已过 [now] 创建日期的）。
  Future<List<ConfirmationTask>> due(
    DatabaseExecutor db,
    DateTime now,
  ) async {
    final rows = await db.query(
      table,
      where: "status = 'open' AND (due_at IS NULL OR due_at <= ?)",
      whereArgs: <Object?>[now.toIso8601String()],
      orderBy: 'COALESCE(due_at, created_at) ASC',
    );
    return rows.map(fromRow).toList();
  }

  Future<int> resolve(
    DatabaseExecutor db,
    String id,
    String status, {
    DateTime? at,
  }) {
    return db.update(
      table,
      <String, Object?>{
        'status': status,
        'resolved_at': (at ?? DateTime.now()).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 同类型同一天只建一条，避免反复弹同一个问题。
  Future<bool> existsOpen(
    DatabaseExecutor db, {
    required String kind,
    DayKey? day,
    String? behaviorCode,
  }) async {
    final rows = await db.query(
      table,
      columns: <String>['id'],
      where: 'status = ? AND kind = ? AND COALESCE(day_key, \'\') = ? '
          'AND COALESCE(behavior_code, \'\') = ?',
      whereArgs: <Object?>[
        'open',
        kind,
        day?.iso ?? '',
        behaviorCode ?? '',
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> countOpen(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM $table WHERE status = 'open'",
    );
    return asInt(rows.first['c']);
  }

  Map<String, Object?> toRow(ConfirmationTask t) => <String, Object?>{
        'id': t.id,
        'day_key': t.dayKey?.iso,
        'behavior_code': t.behaviorCode,
        'kind': t.kind,
        'title': t.title,
        'detail': t.detail,
        'status': t.status,
        'payload_json': encodeJsonMap(t.payload),
        'due_at': t.dueAt?.toIso8601String(),
        'created_at': t.createdAt.toIso8601String(),
        'resolved_at': t.resolvedAt?.toIso8601String(),
      };

  ConfirmationTask fromRow(Map<String, Object?> r) {
    final dayRaw = r['day_key'];
    return ConfirmationTask(
      id: r['id']?.toString() ?? '',
      kind: r['kind']?.toString() ?? '',
      title: r['title']?.toString() ?? '',
      createdAt: parseDate(r['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dayKey: dayRaw == null ? null : DayKey.parse(dayRaw.toString()),
      behaviorCode: r['behavior_code']?.toString(),
      detail: r['detail']?.toString() ?? '',
      status: r['status']?.toString() ?? 'open',
      payload: decodeMap(r['payload_json']?.toString()),
      dueAt: parseDate(r['due_at']),
      resolvedAt: parseDate(r['resolved_at']),
    );
  }
}
