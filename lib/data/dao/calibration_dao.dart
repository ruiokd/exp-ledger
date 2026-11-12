/// `calibration_record` 读写。
///
/// 只追加、不改写：校准是历史事实，改了就失去"从自报变实测"的可追溯性。
library;

import 'dart:convert';

import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class CalibrationDao {
  const CalibrationDao();

  static const String table = Tables.calibrationRecord;

  Future<void> insert(DatabaseExecutor db, CalibrationRecord r) async {
    await db.insert(
      table,
      toRow(r),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CalibrationRecord?> latest(
    DatabaseExecutor db,
    String kind,
  ) async {
    final rows = await db.query(
      table,
      where: 'kind = ?',
      whereArgs: <Object?>[kind],
      orderBy: 'performed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<List<CalibrationRecord>> recent(
    DatabaseExecutor db, {
    int limit = 20,
  }) async {
    final rows = await db.query(
      table,
      orderBy: 'performed_at DESC',
      limit: limit,
    );
    return rows.map(fromRow).toList();
  }

  Future<int> countForAxis(DatabaseExecutor db, ProjectAxis axis) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE axis = ?',
      <Object?>[axis.name],
    );
    return asInt(rows.first['c']);
  }

  Map<String, Object?> toRow(CalibrationRecord r) => <String, Object?>{
        'id': r.id,
        'kind': r.kind,
        'axis': r.axis.name,
        'measured_value': r.measuredValue,
        'unit': r.unit,
        'source': r.source,
        'confidence_before': r.confidenceBefore.name,
        'confidence_after': r.confidenceAfter.name,
        'raw_json': encodeJsonMap(r.raw),
        'performed_at': r.performedAt.toIso8601String(),
        'created_at': (r.createdAt ?? DateTime.now()).toIso8601String(),
      };

  CalibrationRecord fromRow(Map<String, Object?> r) => CalibrationRecord(
        id: r['id']?.toString() ?? '',
        kind: r['kind']?.toString() ?? '',
        axis: ProjectAxis.parse(r['axis']?.toString() ?? 'strength'),
        measuredValue: asDouble(r['measured_value']),
        unit: r['unit']?.toString() ?? '',
        source: r['source']?.toString() ?? 'manual',
        confidenceBefore: Confidence.parse(
          r['confidence_before']?.toString() ?? 'selfReport',
        ),
        confidenceAfter: Confidence.parse(
          r['confidence_after']?.toString() ?? 'selfReport',
        ),
        raw: _decodeRaw(r['raw_json']?.toString()),
        performedAt: parseDate(r['performed_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        createdAt: parseDate(r['created_at']),
      );

  Map<String, Object?> _decodeRaw(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, Object?>{};
    try {
      final v = jsonDecode(raw);
      if (v is Map) {
        return v.map<String, Object?>(
          (Object? k, Object? val) => MapEntry<String, Object?>('$k', val),
        );
      }
    } on FormatException {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }
}
