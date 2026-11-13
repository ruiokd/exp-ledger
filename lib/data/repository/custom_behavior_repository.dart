/// 自建项目的生命周期：建、列、删。
///
/// **建 = 一个事务写三处**：行为本身（custom_behavior）、刻度（user_anchor）、
/// 先验量级（declared_impact）。少写一处就会得到"库里有了但记不了"或
/// "能记但刻度页看不到"的半成品。
library;

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/data/dao/anchor_dao.dart';
import 'package:exp_ledger/data/dao/custom_behavior_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class CustomBehaviorRepository {
  CustomBehaviorRepository({
    required AppDatabase database,
    AnchorEngine engine = const AnchorEngine(),
  })  : _db = database.db,
        _engine = engine;

  final Database _db;
  final AnchorEngine _engine;
  final CustomBehaviorDao _dao = const CustomBehaviorDao();
  final AnchorDao _anchors = const AnchorDao();

  Future<List<CustomBehaviorRecord>> list() => _dao.enabled(_db);

  Future<CustomBehaviorRecord?> byCode(String code) => _dao.byCode(_db, code);

  /// 删掉一个自建项目（连同它的刻度与证据）。
  Future<void> remove(String code) async {
    await _db.transaction<void>((Transaction txn) async {
      await txn.delete(
        Tables.anchorEvidence,
        where: 'behavior_id = ?',
        whereArgs: <Object?>[code],
      );
      await txn.delete(
        Tables.declaredImpact,
        where: 'behavior_id = ?',
        whereArgs: <Object?>[code],
      );
      await txn.delete(
        Tables.anchorRevision,
        where: 'behavior_id = ?',
        whereArgs: <Object?>[code],
      );
      await txn.delete(
        Tables.userAnchor,
        where: 'behavior_id = ?',
        whereArgs: <Object?>[code],
      );
      await _dao.delete(txn, code);
    });
    logInfo('custom', '删除自建项目 $code');
  }

  /// 建一个新项目。返回它，[BehaviorDef] 由 `customBehaviorDef()` 生成。
  Future<CustomBehaviorRecord> create({
    required String name,
    required BehaviorCategory category,
    required ProjectAxis axis,
    required MeasurementClass measurementClass,
    required String unitLabel,
    required String definitionText,
    required double targetDose,
    required String doseUnit,
    required ImpactTier tier,
    String description = '',
    String referenceObject = '',
    String referenceRangeId = 'custom',
    String note = '',
    DateTime? at,
  }) async {
    final DateTime now = at ?? DateTime.now();
    final String code = customBehaviorCode(now);
    final CustomBehaviorRecord record = CustomBehaviorRecord(
      code: code,
      name: name.trim(),
      description: description.trim(),
      category: category,
      axis: axis,
      measurementClass: measurementClass,
      unitLabel: unitLabel.trim(),
      definitionText: definitionText.trim(),
      targetDose: targetDose <= 0 ? 1 : targetDose,
      doseUnit: doseUnit.trim().isEmpty ? '次' : doseUnit.trim(),
      tier: tier,
      createdAt: now,
    );

    final UserAnchor anchor = UserAnchor(
      behaviorId: code,
      unitLabel: record.unitLabel,
      definitionText: record.definitionText,
      referenceObject: referenceObject,
      measurementClass: measurementClass,
      referenceRangeId: referenceRangeId,
      calibratedAt: now,
    );

    // 先验：用户确认过 AI 的提案，所以身份是 userPrior（它就是你的判断）。
    final DeclaredImpact impact = _engine.declare(
      behaviorId: code,
      tier: tier,
      source: ImpactSource.userPrior,
      at: now,
      note: note.isEmpty ? '自建项目' : note,
    );

    await _db.transaction<void>((Transaction txn) async {
      await _dao.upsert(txn, record, now: now);
      await _anchors.upsertAnchor(txn, anchor, now: now);
      await _anchors.upsertImpact(txn, impact, now: now);
    });

    logInfo(
      'custom',
      '新建项目 ${record.name}',
      detail: 'code=$code axis=${axis.name} cat=${category.name} '
          'class=${measurementClass.name} tier=${tier.name} '
          'target=${record.targetDose}${record.doseUnit}',
    );
    return record;
  }
}
