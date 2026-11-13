/// `custom_behavior` 读写。只搬行，不做业务判定。
library;

import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/anchor/anchor_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class CustomBehaviorDao {
  const CustomBehaviorDao();

  static const String table = Tables.customBehavior;

  Future<void> upsert(
    DatabaseExecutor db,
    CustomBehaviorRecord r, {
    required DateTime now,
  }) async {
    await db.insert(
      table,
      <String, Object?>{
        'code': r.code,
        'name': r.name,
        'description': r.description,
        'category': r.category.name,
        'axis': r.axis.name,
        'measurement_class': r.measurementClass.name,
        'unit_label': r.unitLabel,
        'definition_text': r.definitionText,
        'target_dose': r.targetDose,
        'dose_unit': r.doseUnit,
        'tier': r.tier.name,
        'enabled': r.enabled ? 1 : 0,
        'created_at': r.createdAt.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CustomBehaviorRecord>> enabled(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'enabled = 1',
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<CustomBehaviorRecord>> all(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows =
        await db.query(table, orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<CustomBehaviorRecord?> byCode(
    DatabaseExecutor db,
    String code,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'code = ?',
      whereArgs: <Object?>[code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> delete(DatabaseExecutor db, String code) async {
    await db.delete(table, where: 'code = ?', whereArgs: <Object?>[code]);
  }

  CustomBehaviorRecord _fromRow(Map<String, Object?> r) => CustomBehaviorRecord(
        code: r['code']?.toString() ?? '',
        name: r['name']?.toString() ?? '',
        description: r['description']?.toString() ?? '',
        category: _category(r['category']?.toString() ?? ''),
        axis: ProjectAxis.parse(r['axis']?.toString() ?? 'discipline'),
        measurementClass:
            MeasurementClass.parse(r['measurement_class']?.toString() ?? ''),
        unitLabel: r['unit_label']?.toString() ?? '',
        definitionText: r['definition_text']?.toString() ?? '',
        targetDose: (r['target_dose'] as num?)?.toDouble() ?? 1,
        doseUnit: r['dose_unit']?.toString() ?? '次',
        tier: ImpactTier.parse(r['tier']?.toString() ?? ''),
        enabled: (r['enabled'] as num?)?.toInt() != 0,
        createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
            DateTime(1970),
      );

  BehaviorCategory _category(String raw) {
    for (final BehaviorCategory c in BehaviorCategory.values) {
      if (c.name == raw) return c;
    }
    return BehaviorCategory.positive;
  }
}
