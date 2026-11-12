/// `forecast_point` 读写。
///
/// 语义约定（重要，别混）：
///   `day_key`      = **哪一天做出的预测**（生成日）
///   `horizon_days` = 从生成日往后第几天（0 = 当天实际值）
///
/// 所以：
///   - 主图的历史实际线读 `horizon_days = 0`；
///   - "今天往前看 90 天"读 `day_key = 今天` 的全部行。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class ForecastPointDao {
  const ForecastPointDao();

  static const String table = Tables.forecastPoint;

  /// 某一天的预测整批替换（含 horizon = 0 的实际点）。
  Future<void> replaceForDay(
    DatabaseExecutor db,
    DayKey generatedOn,
    Map<ProjectAxis, List<ForecastPoint>> byAxis,
  ) async {
    await db.delete(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[generatedOn.iso],
    );
    final batch = db.batch();
    for (final entry in byAxis.entries) {
      for (final point in entry.value) {
        batch.insert(
          table,
          toRow(generatedOn, entry.key, point),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// 读某天做出的全部预测，按轴分组。
  Future<Map<ProjectAxis, List<ForecastPoint>>> forDay(
    DatabaseExecutor db,
    DayKey generatedOn,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[generatedOn.iso],
      orderBy: 'axis ASC, horizon_days ASC',
    );
    final out = <ProjectAxis, List<ForecastPoint>>{};
    for (final r in rows) {
      final axis = ProjectAxis.parse(r['axis'].toString());
      out.putIfAbsent(axis, () => <ForecastPoint>[]).add(fromRow(r));
    }
    return out;
  }

  /// 某个轴的实际值序列（horizon = 0），用于主图历史部分。
  Future<List<ForecastPoint>> actualSeries(
    DatabaseExecutor db,
    ProjectAxis axis,
    DayKey from,
    DayKey to,
  ) async {
    final rows = await db.query(
      table,
      where: 'axis = ? AND horizon_days = 0 AND day_key >= ? AND day_key <= ?',
      whereArgs: <Object?>[axis.name, from.iso, to.iso],
      orderBy: 'day_key ASC',
    );
    return rows.map(fromRow).toList();
  }

  /// 某个轴的预测序列（生成日 = [generatedOn]，horizon > 0）。
  Future<List<ForecastPoint>> projectionSeries(
    DatabaseExecutor db,
    ProjectAxis axis,
    DayKey generatedOn,
  ) async {
    final rows = await db.query(
      table,
      where: 'axis = ? AND day_key = ? AND horizon_days > 0',
      whereArgs: <Object?>[axis.name, generatedOn.iso],
      orderBy: 'horizon_days ASC',
    );
    return rows.map(fromRow).toList();
  }

  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(
    DayKey generatedOn,
    ProjectAxis axis,
    ForecastPoint p,
  ) =>
      <String, Object?>{
        'day_key': generatedOn.iso,
        'axis': axis.name,
        'horizon_days': p.day.diffDays(generatedOn),
        'maintain': p.maintain,
        'correct': p.correct,
        'low': p.low,
        'high': p.high,
        'confidence': p.confidence,
        'is_projection': boolToInt(p.isProjection),
      };

  /// 注意：`day_key` 列在这个方法里是**目标日**（由 horizon 推回）。
  /// 读出来时按 DAO 的语义还原：目标日 = 生成日 + horizon。
  ForecastPoint fromRow(Map<String, Object?> r) {
    final generated = DayKey.parse(r['day_key'].toString());
    final horizon = asInt(r['horizon_days']);
    return ForecastPoint(
      day: generated.addDays(horizon),
      maintain: asDouble(r['maintain']),
      correct: asDouble(r['correct']),
      low: asDouble(r['low']),
      high: asDouble(r['high']),
      confidence: asDouble(r['confidence'], fallback: 1),
      isProjection: asBool(r['is_projection']),
    );
  }
}
