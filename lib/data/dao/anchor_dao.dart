/// `user_anchor` / `anchor_revision` / `declared_impact` / `anchor_evidence`
/// 四张表的读写。
///
/// 规矩（和别的 DAO 一致）：
///   - 这里只做行 ↔ 模型的搬运，不判定任何业务（判定在 `AnchorEngine`）；
///   - 时间一律 ISO8601 字符串，解析失败退化成 1970，不抛；
///   - 证据表**只追加**：没有 update / delete 方法，这是故意的。
library;

import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:sqflite/sqflite.dart';

class AnchorDao {
  const AnchorDao();

  static const String anchors = Tables.userAnchor;
  static const String revisions = Tables.anchorRevision;
  static const String impacts = Tables.declaredImpact;
  static const String evidences = Tables.anchorEvidence;

  static DateTime _time(Object? raw, {DateTime? fallback}) =>
      DateTime.tryParse(raw?.toString() ?? '') ?? fallback ?? DateTime(1970);

  static double _real(Object? raw) => (raw as num?)?.toDouble() ?? 0;

  // ---------------------------------------------------------------- 刻度

  Future<void> upsertAnchor(
    DatabaseExecutor db,
    UserAnchor anchor, {
    required DateTime now,
  }) async {
    await db.insert(
      anchors,
      <String, Object?>{
        'behavior_id': anchor.behaviorId,
        'unit_label': anchor.unitLabel,
        'definition_text': anchor.definitionText,
        'reference_object': anchor.referenceObject,
        'measurement_class': anchor.measurementClass.name,
        'reference_range_id': anchor.referenceRangeId,
        'calibrated_at': anchor.calibratedAt.toIso8601String(),
        'created_at': anchor.calibratedAt.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserAnchor?> anchorOf(DatabaseExecutor db, String behaviorId) async {
    final List<Map<String, Object?>> rows = await db.query(
      anchors,
      where: 'behavior_id = ?',
      whereArgs: <Object?>[behaviorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final List<AnchorRevision> history = await revisionsOf(db, behaviorId);
    return _anchorFromRow(rows.first, history);
  }

  Future<List<UserAnchor>> allAnchors(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows =
        await db.query(anchors, orderBy: 'updated_at DESC');
    final List<UserAnchor> out = <UserAnchor>[];
    for (final Map<String, Object?> row in rows) {
      final String id = row['behavior_id']?.toString() ?? '';
      out.add(_anchorFromRow(row, await revisionsOf(db, id)));
    }
    return out;
  }

  UserAnchor _anchorFromRow(
    Map<String, Object?> row,
    List<AnchorRevision> history,
  ) =>
      UserAnchor(
        behaviorId: row['behavior_id']?.toString() ?? '',
        unitLabel: row['unit_label']?.toString() ?? '',
        definitionText: row['definition_text']?.toString() ?? '',
        referenceObject: row['reference_object']?.toString() ?? '',
        measurementClass:
            MeasurementClass.parse(row['measurement_class']?.toString() ?? ''),
        referenceRangeId:
            row['reference_range_id']?.toString() ?? 'custom',
        calibratedAt: _time(row['calibrated_at']),
        revisionHistory: history,
      );

  // ---------------------------------------------------------------- 变更链

  Future<void> appendRevisions(
    DatabaseExecutor db,
    String behaviorId,
    List<AnchorRevision> items,
  ) async {
    for (final AnchorRevision r in items) {
      await db.insert(revisions, <String, Object?>{
        'behavior_id': behaviorId,
        'field': r.field,
        'from_value': r.from,
        'to_value': r.to,
        'reason': r.reason,
        'changed_at': r.at.toIso8601String(),
      });
    }
  }

  Future<List<AnchorRevision>> revisionsOf(
    DatabaseExecutor db,
    String behaviorId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      revisions,
      where: 'behavior_id = ?',
      whereArgs: <Object?>[behaviorId],
      orderBy: 'changed_at ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> r) => AnchorRevision(
              at: _time(r['changed_at']),
              field: r['field']?.toString() ?? '',
              from: r['from_value']?.toString() ?? '',
              to: r['to_value']?.toString() ?? '',
              reason: r['reason']?.toString() ?? '',
            ))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------- 先验

  Future<void> upsertImpact(
    DatabaseExecutor db,
    DeclaredImpact impact, {
    required DateTime now,
  }) async {
    await db.insert(
      impacts,
      <String, Object?>{
        'behavior_id': impact.behaviorId,
        'tier': impact.tier.name,
        'source': impact.source.name,
        'weight': impact.weight,
        'declared_at': impact.declaredAt.toIso8601String(),
        'replaced_by': impact.replacedBy,
        'note': impact.note,
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DeclaredImpact?> impactOf(
    DatabaseExecutor db,
    String behaviorId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      impacts,
      where: 'behavior_id = ?',
      whereArgs: <Object?>[behaviorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;
    return DeclaredImpact(
      behaviorId: r['behavior_id']?.toString() ?? behaviorId,
      tier: ImpactTier.parse(r['tier']?.toString() ?? ''),
      source: ImpactSource.parse(r['source']?.toString() ?? ''),
      weight: _real(r['weight']),
      declaredAt: _time(r['declared_at']),
      replacedBy: r['replaced_by']?.toString(),
      note: r['note']?.toString() ?? '',
    );
  }

  Future<List<DeclaredImpact>> allImpacts(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows =
        await db.query(impacts, orderBy: 'updated_at DESC');
    return rows
        .map((Map<String, Object?> r) => DeclaredImpact(
              behaviorId: r['behavior_id']?.toString() ?? '',
              tier: ImpactTier.parse(r['tier']?.toString() ?? ''),
              source: ImpactSource.parse(r['source']?.toString() ?? ''),
              weight: _real(r['weight']),
              declaredAt: _time(r['declared_at']),
              replacedBy: r['replaced_by']?.toString(),
              note: r['note']?.toString() ?? '',
            ))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------- 证据

  Future<void> insertEvidence(
    DatabaseExecutor db,
    AnchorEvidence evidence, {
    required DateTime now,
  }) async {
    await db.insert(
      evidences,
      <String, Object?>{
        'id': evidence.id,
        'behavior_id': evidence.behaviorId,
        'kind': evidence.kind.name,
        'measured_value': evidence.measuredValue,
        'unit': evidence.unit,
        'derived_tier': evidence.derivedTier.name,
        'performed_at': evidence.performedAt.toIso8601String(),
        'note': evidence.note,
        'confidence': evidence.confidence.name,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AnchorEvidence?> latestEvidence(
    DatabaseExecutor db,
    String behaviorId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      evidences,
      where: 'behavior_id = ?',
      whereArgs: <Object?>[behaviorId],
      orderBy: 'performed_at DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _evidenceFromRow(rows.first);
  }

  Future<List<AnchorEvidence>> evidenceOf(
    DatabaseExecutor db,
    String behaviorId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      evidences,
      where: 'behavior_id = ?',
      whereArgs: <Object?>[behaviorId],
      orderBy: 'performed_at DESC, created_at DESC',
    );
    return rows.map(_evidenceFromRow).toList(growable: false);
  }

  Future<List<AnchorEvidence>> allEvidence(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      evidences,
      orderBy: 'performed_at DESC',
    );
    return rows.map(_evidenceFromRow).toList(growable: false);
  }

  AnchorEvidence _evidenceFromRow(Map<String, Object?> r) => AnchorEvidence(
        id: r['id']?.toString() ?? '',
        behaviorId: r['behavior_id']?.toString() ?? '',
        kind: EvidenceKind.parse(r['kind']?.toString() ?? ''),
        measuredValue: _real(r['measured_value']),
        unit: r['unit']?.toString() ?? '',
        derivedTier: ImpactTier.parse(r['derived_tier']?.toString() ?? ''),
        performedAt: _time(r['performed_at']),
        note: r['note']?.toString() ?? '',
        confidence: Confidence.parse(r['confidence']?.toString() ?? ''),
      );
}
