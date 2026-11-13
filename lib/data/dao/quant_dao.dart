/// `behavior_quant_spec` / `axis_definition` 读写。只搬行，不做业务判定。
///
/// 两条规矩：
///   1. 这里的每个方法都收 `DatabaseExecutor`，所以既能直接用 [Database]，
///      也能在事务里用 `txn` 传进来（铁律：事务体内只能用 txn）。
///   2. 不做校验。"形状白名单、份额合计、能力维度要不要衰减依据"全部在
///      `domain/quant` 判定完再进来。DAO 只负责把判好的东西按列摆好。
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:sqflite/sqflite.dart';

class QuantDao {
  const QuantDao();

  static const String specTable = Tables.behaviorQuantSpec;
  static const String axisTable = Tables.axisDefinition;

  // ---------------------------------------------------------------- 量化规格

  /// 全部规格，按行为码索引。解析不了的行跳过（不猜、不回退成 linear）。
  Future<Map<String, QuantSpec>> specs(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows =
        await db.query(specTable, orderBy: 'updated_at DESC');
    final Map<String, QuantSpec> out = <String, QuantSpec>{};
    int skipped = 0;
    for (final Map<String, Object?> r in rows) {
      final QuantSpec? spec = _specFromRow(r);
      if (spec == null) {
        skipped++;
        continue;
      }
      out[spec.behaviorCode] = spec;
    }
    if (skipped > 0) {
      // 只记数量，不记内容：日志是要被复制出去发人的（六之十三）。
      developer.log('跳过 $skipped 条无法解析的量化规格',
          name: 'QuantDao', level: 900);
    }
    return out;
  }

  Future<QuantSpec?> specByCode(DatabaseExecutor db, String code) async {
    final List<Map<String, Object?>> rows = await db.query(
      specTable,
      where: 'behavior_code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _specFromRow(rows.first);
  }

  /// 写入一条规格。
  ///
  /// 用「先读后写」而不是 `INSERT ... ON CONFLICT DO UPDATE`：
  /// minSdk 23 上的 SQLite 是 3.8，不支持 upsert 语法。
  /// 读的两列是 `created_at`（保留首次写入时间）与 `revision`（改一次 +1，
  /// 改口径要留痕——「你 3 月把线性改成了递减」这句话得查得到）。
  Future<void> upsertSpec(
    DatabaseExecutor db,
    QuantSpec spec, {
    required DateTime now,
  }) async {
    final List<Map<String, Object?>> existing = await db.query(
      specTable,
      columns: <String>['created_at', 'revision'],
      where: 'behavior_code = ?',
      whereArgs: <Object?>[spec.behaviorCode],
      limit: 1,
    );
    final DateTime createdAt = existing.isEmpty
        ? now
        : DateTime.tryParse(existing.first['created_at']?.toString() ?? '') ??
            now;
    final int revision = existing.isEmpty
        ? 1
        : ((existing.first['revision'] as num?)?.toInt() ?? 1) + 1;

    await db.insert(
      specTable,
      <String, Object?>{
        'behavior_code': spec.behaviorCode,
        'measure_kind': spec.measureKind.name,
        'measure_unit': spec.measureUnit,
        'how_to_check': spec.howToCheck,
        'shape_kind': spec.shape.kind.name,
        'shape_k': spec.shape.kind == DoseShape.log ? spec.shape.logK : null,
        'shape_theta_fraction':
            spec.shape.kind == DoseShape.threshold ? spec.shape.thetaFraction : null,
        'target_dose': spec.targetDose,
        'impact_json':
            jsonEncode(spec.impact.map((ImpactShare s) => s.toJson()).toList()),
        'citation': spec.citation,
        'source': spec.source,
        'note': spec.note,
        'revision': revision,
        'created_at': createdAt.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSpec(DatabaseExecutor db, String code) async {
    await db.delete(specTable,
        where: 'behavior_code = ?', whereArgs: <Object?>[code]);
  }

  Future<void> deleteSpecsLike(DatabaseExecutor db, String prefix) async {
    await db.delete(
      specTable,
      where: 'behavior_code LIKE ?',
      whereArgs: <Object?>['$prefix%'],
    );
  }

  // ---------------------------------------------------------------- 自定义维度

  Future<List<AxisSpec>> axes(
    DatabaseExecutor db, {
    bool enabledOnly = true,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      axisTable,
      where: enabledOnly ? 'enabled = 1' : null,
      orderBy: 'created_at ASC',
    );
    return rows.map(_axisFromRow).toList(growable: false);
  }

  Future<AxisSpec?> axisByKey(DatabaseExecutor db, String key) async {
    final List<Map<String, Object?>> rows = await db.query(
      axisTable,
      where: 'axis_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _axisFromRow(rows.first);
  }

  Future<void> upsertAxis(
    DatabaseExecutor db,
    AxisSpec axis, {
    required DateTime now,
  }) async {
    final List<Map<String, Object?>> existing = await db.query(
      axisTable,
      columns: <String>['created_at'],
      where: 'axis_key = ?',
      whereArgs: <Object?>[axis.key],
      limit: 1,
    );
    final DateTime createdAt = existing.isEmpty
        ? now
        : DateTime.tryParse(existing.first['created_at']?.toString() ?? '') ??
            now;
    await db.insert(
      axisTable,
      <String, Object?>{
        'axis_key': axis.key,
        'label': axis.label,
        'dim_kind': axis.kind.name,
        'decay_tau_days': axis.isAbility ? axis.decayTauDays : 0,
        'decay_citation': axis.decayCitation,
        'enabled': 1,
        'created_at': createdAt.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAxis(DatabaseExecutor db, String key) async {
    await db.delete(axisTable,
        where: 'axis_key = ?', whereArgs: <Object?>[key]);
  }

  // ---------------------------------------------------------------- 行 → 模型

  QuantSpec? _specFromRow(Map<String, Object?> r) {
    final String code = r['behavior_code']?.toString() ?? '';
    if (code.isEmpty) return null;
    final MeasureKind? kind =
        MeasureKind.tryParse(r['measure_kind']?.toString());
    if (kind == null) return null;

    final List<ImpactShare> impact = <ImpactShare>[];
    final Object? raw = _decodeJson(r['impact_json']);
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final ImpactShare? s =
            ImpactShare.fromJson(Map<String, Object?>.from(item));
        if (s != null) impact.add(s);
      }
    }

    final DoseShape shape = DoseShape.parseOrDefault(r['shape_kind']?.toString());
    return QuantSpec(
      behaviorCode: code,
      measureKind: kind,
      measureUnit: r['measure_unit']?.toString() ?? kind.defaultUnit,
      shape: DoseShapeSpec(
        kind: shape,
        logK: (r['shape_k'] as num?)?.toDouble() ?? 1,
        thetaFraction: (r['shape_theta_fraction'] as num?)?.toDouble() ?? 1,
      ),
      targetDose: (r['target_dose'] as num?)?.toDouble() ?? 0,
      impact: impact,
      howToCheck: r['how_to_check']?.toString() ?? '',
      citation: r['citation']?.toString() ?? '',
      source: r['source']?.toString() ?? 'userPrior',
      note: r['note']?.toString() ?? '',
    );
  }

  AxisSpec _axisFromRow(Map<String, Object?> r) => AxisSpec(
        key: r['axis_key']?.toString() ?? '',
        label: r['label']?.toString() ?? '',
        kind: AxisKind.parseOrDefault(r['dim_kind']?.toString()),
        decayTauDays: (r['decay_tau_days'] as num?)?.toDouble() ?? 0,
        decayCitation: r['decay_citation']?.toString() ?? '',
      );

  Object? _decodeJson(Object? raw) {
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
