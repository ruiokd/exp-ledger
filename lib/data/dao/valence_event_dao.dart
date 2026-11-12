/// `valence_event` 读写。
///
/// 正向事件是**结算产物**，不是用户输入：同一天重算时会整批替换。
/// 唯一索引 `(day_key, behavior_code, slot_key)` 保证同槽位不会出现两条。
///
/// 槽位不写在 [ValenceEvent] 模型里（domain 不需要它），
/// 由 `id` 解析得到——见 `db/ids.dart`。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/ids.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';
import 'package:sqflite/sqflite.dart';

class ValenceEventDao {
  const ValenceEventDao();

  static const String table = Tables.valenceEvent;

  /// 整天的产物一次性替换。重算的唯一写入口。
  Future<void> replaceDay(
    DatabaseExecutor db,
    DayKey day,
    List<ValenceEvent> events,
  ) async {
    await db.delete(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
    );
    if (events.isEmpty) return;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(
        table,
        toRow(e),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertMany(
    DatabaseExecutor db,
    List<ValenceEvent> events,
  ) async {
    if (events.isEmpty) return;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(
        table,
        toRow(e),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ValenceEvent>> byDay(DatabaseExecutor db, DayKey day) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'exp DESC',
    );
    return rows.map(fromRow).toList();
  }

  /// 近 [days] 天某轴的 EXP 合计（含今天）。
  Future<double> sumExpForAxis(
    DatabaseExecutor db,
    ProjectAxis axis,
    DayKey through,
    int days,
  ) async {
    final from = through.addDays(-(days - 1));
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(exp), 0) AS s
      FROM $table
      WHERE axis = ? AND day_key >= ? AND day_key <= ?
      ''',
      <Object?>[axis.name, from.iso, through.iso],
    );
    return asDouble(rows.first['s']);
  }

  Future<int> deleteFrom(DatabaseExecutor db, DayKey from) => db.delete(
        table,
        where: 'day_key >= ?',
        whereArgs: <Object?>[from.iso],
      );

  Map<String, Object?> toRow(ValenceEvent e) => <String, Object?>{
        'id': e.id,
        'day_key': e.dayKey.iso,
        'behavior_code': e.behaviorCode,
        'behavior_name': e.behaviorName,
        'slot_key': slotKeyOfEventId(e.id),
        'valence': e.valence.name,
        'axis': e.axis.name,
        'base_score': e.baseScore,
        'quality_bonus': e.qualityBonus,
        'efficiency_bonus': e.efficiencyBonus,
        'normalized_score': e.normalizedScore,
        'weight': e.weight,
        'state_multiplier': e.stateMultiplier,
        'confidence_weight': e.confidenceWeight,
        'exp': e.exp,
        'confidence': e.confidence.name,
        'notes_json': encodeJsonList(e.notes),
        'breakdown_json': encodeJsonMap(
          e.breakdown.map<String, Object?>(
            (String k, double v) => MapEntry<String, Object?>(k, v),
          ),
        ),
        'estimated': boolToInt(e.estimated),
      };

  ValenceEvent fromRow(Map<String, Object?> r) => ValenceEvent(
        id: r['id']?.toString() ?? '',
        dayKey: DayKey.parse(r['day_key'].toString()),
        behaviorCode: r['behavior_code']?.toString() ?? '',
        behaviorName: r['behavior_name']?.toString() ?? '',
        valence: parseEnum<Valence>(
          Valence.values,
          r['valence'],
          Valence.positive,
        ),
        axis: ProjectAxis.parse(r['axis']?.toString() ?? 'strength'),
        baseScore: asDouble(r['base_score']),
        qualityBonus: asDouble(r['quality_bonus']),
        efficiencyBonus: asDouble(r['efficiency_bonus']),
        normalizedScore: asDouble(r['normalized_score']),
        weight: asDouble(r['weight'], fallback: 1),
        stateMultiplier: asDouble(r['state_multiplier'], fallback: 1),
        confidenceWeight: asDouble(r['confidence_weight'], fallback: 1),
        exp: asDouble(r['exp']),
        confidence: Confidence.parse(r['confidence']?.toString() ?? 'selfReport'),
        notes: decodeStringList(r['notes_json']?.toString()),
        breakdown: decodeDoubleMap(r['breakdown_json']?.toString()),
        estimated: asBool(r['estimated']),
      );
}
