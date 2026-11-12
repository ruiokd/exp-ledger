/// `daily_log` 读写。
///
/// 这张表是**原始事实**：用户说过什么就存什么，不含任何算出来的分数。
/// 幂等键 `dayKey|behaviorCode|slotKey` 上有唯一索引，重复写入只会覆盖。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class DailyLogDao {
  const DailyLogDao();

  static const String table = Tables.dailyLog;

  /// 写入一行。冲突策略交给调用方：首次写入用 [insert]，
  /// 修订用 [replace]（配合 history 归档）。
  Future<int> insert(DatabaseExecutor db, DraftEntry entry) =>
      db.insert(table, toRow(entry));

  Future<int> replace(DatabaseExecutor db, DraftEntry entry) => db.insert(
        table,
        toRow(entry),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<DraftEntry?> byIdempotencyKey(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      table,
      where: 'idempotency_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  /// 原始行（含所有列）。修订时要把它整行归档，所以不能在读取时解码再编码。
  Future<Map<String, Object?>?> rawByKey(
    DatabaseExecutor db,
    String key,
  ) async {
    final rows = await db.query(
      table,
      where: 'idempotency_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<DraftEntry>> byDay(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(fromRow).toList();
  }

  /// 闭区间 [from, to]。用于导出、周报、以及"最近 N 天"的统计。
  Future<List<DraftEntry>> between(
    DatabaseExecutor db,
    DayKey from,
    DayKey to,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key >= ? AND day_key <= ?',
      whereArgs: <Object?>[from.iso, to.iso],
      orderBy: 'day_key ASC, created_at ASC',
    );
    return rows.map(fromRow).toList();
  }

  Future<int> deleteByDay(DatabaseExecutor db, DayKey day) => db.delete(
        table,
        where: 'day_key = ?',
        whereArgs: <Object?>[day.iso],
      );

  /// 删除单条（用户撤销一次录入）。返回受影响行数。
  Future<int> deleteByIdempotencyKey(DatabaseExecutor db, String key) =>
      db.delete(
        table,
        where: 'idempotency_key = ?',
        whereArgs: <Object?>[key],
      );

  /// "同上一次"要用：取该行为最近一次的答案。
  Future<Map<String, Object?>?> lastAnswers(
    DatabaseExecutor db,
    String behaviorCode,
  ) async {
    final rows = await db.query(
      table,
      columns: <String>['answers_json'],
      where: 'behavior_code = ?',
      whereArgs: <Object?>[behaviorCode],
      orderBy: 'day_key DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return decodeMap(rows.first['answers_json']?.toString());
  }

  /// 某天记录过的行为码集合（用来判断"计划里的项目今天有没有出现"）。
  Future<Set<String>> behaviorCodesOn(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      columns: <String>['behavior_code'],
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
    );
    return rows
        .map<String>((Map<String, Object?> r) => r['behavior_code'].toString())
        .toSet();
  }

  /// 近 [days] 天里，每个轴"有记录的天数"。快照完整度要用。
  Future<Map<String, int>> daysWithDataPerAxis(
    DatabaseExecutor db,
    DayKey through,
    int days,
  ) async {
    final from = through.addDays(-(days - 1));
    final rows = await db.rawQuery(
      '''
      SELECT axis, COUNT(DISTINCT day_key) AS c
      FROM $table
      WHERE day_key >= ? AND day_key <= ?
      GROUP BY axis
      ''',
      <Object?>[from.iso, through.iso],
    );
    final out = <String, int>{};
    for (final row in rows) {
      out[row['axis'].toString()] = asInt(row['c']);
    }
    return out;
  }

  Future<int> countAll(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return asInt(rows.first['c']);
  }

  /// 行的唯一来源。所有列都在这里显式编码——
  /// sqflite 只接受 num/String/null/Uint8List，直接塞 Map 会抛异常。
  Map<String, Object?> toRow(DraftEntry e, {DateTime? now}) => <String, Object?>{
        'day_key': e.dayKey.iso,
        'behavior_code': e.behaviorCode,
        'category': e.category.name,
        'valence': e.valence.name,
        'axis': e.axis.name,
        'plan_status': e.planStatus.name,
        'confidence': e.confidence.name,
        'slot_key': e.slotKey,
        'idempotency_key': e.idempotencyKey,
        'answers_json': encodeJsonMap(e.answers),
        'metrics_json': encodeJsonMap(
          e.metrics.map<String, Object?>(
            (String k, double v) => MapEntry<String, Object?>(k, v),
          ),
        ),
        'interpretation': e.interpretation,
        'dose_fraction': e.doseFraction,
        'source': e.source,
        'created_at': e.createdAt.toIso8601String(),
        'session_id': e.sessionId,
        'notes_json': encodeJsonList(e.notes),
        'warnings_json': encodeJsonList(e.warnings),
        'revision': e.revision,
        'is_interruption': boolToInt(e.isInterruption),
        'updated_at': (now ?? DateTime.now()).toIso8601String(),
      };

  DraftEntry fromRow(Map<String, Object?> r) => DraftEntry(
        dayKey: DayKey.parse(r['day_key'].toString()),
        behaviorCode: r['behavior_code']?.toString() ?? '',
        category: parseEnum<BehaviorCategory>(
          BehaviorCategory.values,
          r['category'],
          BehaviorCategory.positive,
        ),
        valence: parseEnum<Valence>(
          Valence.values,
          r['valence'],
          Valence.positive,
        ),
        axis: ProjectAxis.parse(r['axis']?.toString() ?? 'strength'),
        planStatus: PlanStatus.parse(r['plan_status']?.toString() ?? 'planned'),
        confidence: Confidence.parse(r['confidence']?.toString() ?? 'selfReport'),
        slotKey: r['slot_key']?.toString() ?? '',
        answers: decodeMap(r['answers_json']?.toString()),
        metrics: decodeDoubleMap(r['metrics_json']?.toString()),
        interpretation: r['interpretation']?.toString() ?? '',
        doseFraction: asDouble(r['dose_fraction']),
        source: r['source']?.toString() ?? 'manual',
        createdAt:
            parseDate(r['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        sessionId: r['session_id']?.toString(),
        notes: decodeStringList(r['notes_json']?.toString()),
        warnings: decodeStringList(r['warnings_json']?.toString()),
        revision: asInt(r['revision']),
        isInterruption: asBool(r['is_interruption']),
      );
}
