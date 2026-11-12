/// `negative_event` 读写。
///
/// 唯一约束只在**主因**上（`WHERE is_primary = 1` 的部分索引）：
/// 同一根因的后果记录可以有多条，它们 exp = 0，只作为痕迹保留。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';
import 'package:sqflite/sqflite.dart';

class NegativeEventDao {
  const NegativeEventDao();

  static const String table = Tables.negativeEvent;

  Future<void> replaceDay(
    DatabaseExecutor db,
    DayKey day,
    List<NegativeEvent> events,
  ) async {
    await db.delete(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
    );
    if (events.isEmpty) return;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(table, toRow(e));
    }
    await batch.commit(noResult: true);
  }

  Future<List<NegativeEvent>> byDay(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'is_primary DESC, exp ASC',
    );
    return rows.map(fromRow).toList();
  }

  /// 结算前要传给流水线的 `existingRootKeys`：今天与昨天已经存在的根因。
  ///
  /// 取的是**已落库**的主因键——所以重算某天之前必须先删掉那天的旧产物，
  /// 否则会把自己上一轮的结果当成"历史已扣过"。
  Future<Set<String>> existingRootKeys(
    DatabaseExecutor db,
    DayKey day, {
    int lookbackDays = 1,
  }) async {
    final from = day.addDays(-lookbackDays);
    final rows = await db.query(
      table,
      columns: <String>['root_cause_key'],
      where: 'day_key >= ? AND day_key <= ? AND is_primary = 1',
      whereArgs: <Object?>[from.iso, day.iso],
    );
    return rows
        .map<String>(
          (Map<String, Object?> r) => r['root_cause_key'].toString(),
        )
        .toSet();
  }

  Future<double> sumExp(
    DatabaseExecutor db,
    DayKey from,
    DayKey to,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(exp), 0) AS s
      FROM $table
      WHERE day_key >= ? AND day_key <= ?
      ''',
      <Object?>[from.iso, to.iso],
    );
    return asDouble(rows.first['s']);
  }

  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(NegativeEvent e) => <String, Object?>{
        'day_key': e.dayKey.iso,
        'behavior_code': e.behaviorCode,
        'behavior_name': e.behaviorName,
        'dose_minutes': e.doseMinutes,
        'penalty_units': e.penaltyUnits,
        'exp': e.exp,
        'root_cause_key': e.rootCauseKey,
        'is_primary': boolToInt(e.isPrimary),
        'suppressed_by': e.suppressedBy,
        'consequences_json': encodeJsonList(e.consequences),
        'recovery_hints_json': encodeJsonList(e.recoveryHints),
        'notes_json': encodeJsonList(e.notes),
      };

  NegativeEvent fromRow(Map<String, Object?> r) => NegativeEvent(
        dayKey: DayKey.parse(r['day_key'].toString()),
        behaviorCode: r['behavior_code']?.toString() ?? '',
        behaviorName: r['behavior_name']?.toString() ?? '',
        doseMinutes: asDouble(r['dose_minutes']),
        penaltyUnits: asDouble(r['penalty_units']),
        exp: asDouble(r['exp']),
        rootCauseKey: r['root_cause_key']?.toString() ?? '',
        isPrimary: asBool(r['is_primary'], fallback: true),
        suppressedBy: r['suppressed_by']?.toString(),
        consequences: decodeStringList(r['consequences_json']?.toString()),
        recoveryHints: decodeStringList(r['recovery_hints_json']?.toString()),
        notes: decodeStringList(r['notes_json']?.toString()),
      );
}
