/// `capture_session` 读写。
///
/// 保存问答轨迹，用途有两个：事后补全（"我当时到底答了什么"）
/// 和问题设计的自我评估（哪一步最常被跳过）。
library;

import 'dart:convert';

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:sqflite/sqflite.dart';

class CaptureSessionDao {
  const CaptureSessionDao();

  static const String table = Tables.captureSession;

  Future<void> save(DatabaseExecutor db, CaptureSession s) async {
    await db.insert(
      table,
      toRow(s),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CaptureSession?> find(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<List<CaptureSession>> forDay(
    DatabaseExecutor db,
    DayKey day,
  ) async {
    final rows = await db.query(
      table,
      where: 'day_key = ?',
      whereArgs: <Object?>[day.iso],
      orderBy: 'started_at ASC',
    );
    return rows.map(fromRow).toList();
  }

  /// 平均录入耗时（秒）。产品目标是 ≤30 秒，用它验证。
  Future<double?> averageDurationSeconds(
    DatabaseExecutor db, {
    int days = 14,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await db.rawQuery(
      '''
      SELECT started_at, ended_at
      FROM $table
      WHERE ended_at IS NOT NULL
        AND abandoned = 0
        AND started_at >= ?
      ''',
      <Object?>[since.toIso8601String()],
    );
    var sum = 0.0;
    var n = 0;
    for (final r in rows) {
      final a = parseDate(r['started_at']);
      final b = parseDate(r['ended_at']);
      if (a == null || b == null) continue;
      sum += b.difference(a).inSeconds.toDouble();
      n++;
    }
    if (n == 0) return null;
    return sum / n;
  }

  Map<String, Object?> toRow(CaptureSession s) => <String, Object?>{
        'id': s.id,
        'started_at': s.startedAt.toIso8601String(),
        'ended_at': s.endedAt?.toIso8601String(),
        'day_key': s.dayKey?.iso,
        'behavior_code': s.behaviorCode,
        'raw_text': s.rawText,
        'stage': s.stage.name,
        'answered_count': s.answeredCount,
        'abandoned': boolToInt(s.abandoned),
        'used_same_as_last': boolToInt(s.usedSameAsLast),
        'used_voice': boolToInt(s.usedVoice),
        'confidence_ceiling': s.confidenceCeiling.name,
        'entry_source': s.entrySource,
        'trace_json': encodeJsonList(s.trace),
      };

  CaptureSession fromRow(Map<String, Object?> r) {
    final dayRaw = r['day_key'];
    return CaptureSession(
      id: r['id']?.toString() ?? '',
      startedAt: parseDate(r['started_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      entrySource: r['entry_source']?.toString() ?? 'manual',
      dayKey: dayRaw == null ? null : DayKey.parse(dayRaw.toString()),
      behaviorCode: r['behavior_code']?.toString(),
      rawText: r['raw_text']?.toString(),
      endedAt: parseDate(r['ended_at']),
      stage: parseEnum<CaptureStage>(
        CaptureStage.values,
        r['stage'],
        CaptureStage.idle,
      ),
      answeredCount: asInt(r['answered_count']),
      abandoned: asBool(r['abandoned']),
      usedSameAsLast: asBool(r['used_same_as_last']),
      usedVoice: asBool(r['used_voice']),
      confidenceCeiling: Confidence.parse(
        r['confidence_ceiling']?.toString() ?? 'calibrated',
      ),
      trace: _decodeTrace(r['trace_json']?.toString()),
    );
  }

  List<Map<String, Object?>> _decodeTrace(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, Object?>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<Object?, Object?>>()
            .map<Map<String, Object?>>(
              (Map<Object?, Object?> m) => m.map<String, Object?>(
                (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
              ),
            )
            .toList();
      }
    } on FormatException {
      return <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[];
  }
}
