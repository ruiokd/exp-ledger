/// 刻度标定层的仓储。**这一层唯一的写入口。**
///
/// 和 `CaptureRepository.commit` 同一个思路：
///   - 一个行为一张卡片（主键 `behavior_id`），重复保存只覆盖；
///   - 刻度变更只追加 revision，不重算历史；
///   - 证据落账必须和"先验被覆盖"在同一个事务里，
///     否则中途失败会留下"有证据但先验还生效"的中间态。
///
/// 本层**不触发结算重算**：先验不进 `SettlementPipeline`（见 ANCHOR-PLUGIN.md）。
library;

import 'package:exp_ledger/data/dao/anchor_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:sqflite/sqflite.dart';

/// 一次档位声明的结果。被拒时 [impact] 为 null，[verdict] 说明原因。
typedef DeclareResult = ({DeclaredImpact? impact, TierChangeVerdict verdict});

class AnchorRepository {
  AnchorRepository({
    required AppDatabase database,
    AnchorEngine engine = const AnchorEngine(),
  })  : _db = database.db,
        _engine = engine;

  final Database _db;
  final AnchorEngine _engine;
  final AnchorDao _dao = const AnchorDao();

  AnchorEngine get engine => _engine;

  // ---------------------------------------------------------------- 读

  Future<List<AnchorCard>> cards() async {
    final List<UserAnchor> anchors = await _dao.allAnchors(_db);
    final List<AnchorCard> out = <AnchorCard>[];
    for (final UserAnchor a in anchors) {
      final DeclaredImpact? impact = await _dao.impactOf(_db, a.behaviorId);
      // 只有刻度、还没声明量级的项不算卡片：一半的卡片会让人以为已经标好了。
      if (impact == null) continue;
      final AnchorEvidence? ev =
          await _dao.latestEvidence(_db, a.behaviorId);
      out.add(AnchorCard(
        behaviorId: a.behaviorId,
        anchor: a,
        impact: impact,
        evidence: ev,
      ));
    }
    return out;
  }

  /// 只读刻度（还没声明量级时也有值）。
  Future<UserAnchor?> anchorOf(String behaviorId) =>
      _dao.anchorOf(_db, behaviorId);

  Future<AnchorCard?> card(String behaviorId) async {
    final UserAnchor? a = await _dao.anchorOf(_db, behaviorId);
    if (a == null) return null;
    final DeclaredImpact? impact = await _dao.impactOf(_db, behaviorId);
    if (impact == null) return null;
    return AnchorCard(
      behaviorId: behaviorId,
      anchor: a,
      impact: impact,
      evidence: await _dao.latestEvidence(_db, behaviorId),
    );
  }

  Future<Map<String, WeightResolution>> resolutions() async {
    final List<AnchorCard> all = await cards();
    final Map<String, WeightResolution> out = <String, WeightResolution>{};
    for (final AnchorCard c in all) {
      out[c.behaviorId] = _engine.resolve(
        impact: c.impact,
        evidence: c.evidence,
        measurementClass: c.measurementClass,
      );
    }
    return out;
  }

  Future<List<AnchorEvidence>> evidenceHistory(String behaviorId) =>
      _dao.evidenceOf(_db, behaviorId);

  // ---------------------------------------------------------------- 写刻度

  /// 保存/修改单位。只追加**新的** revision（旧的已经在库里了）。
  Future<UserAnchor> saveAnchor(UserAnchor anchor, {DateTime? now}) async {
    final DateTime at = now ?? DateTime.now();
    await _db.transaction<void>((Transaction txn) async {
      final List<AnchorRevision> existing =
          await _dao.revisionsOf(txn, anchor.behaviorId);
      await _dao.upsertAnchor(txn, anchor, now: at);
      if (anchor.revisionHistory.length > existing.length) {
        await _dao.appendRevisions(
          txn,
          anchor.behaviorId,
          anchor.revisionHistory.sublist(existing.length),
        );
      }
    });
    return anchor;
  }

  /// 声明量级。走 `AnchorEngine.checkTierChange` 的四道门。
  Future<DeclareResult> declareImpact({
    required String behaviorId,
    required ImpactTier tier,
    required DateTime at,
    ImpactSource source = ImpactSource.userPrior,
    String reason = '',
  }) async {
    final DeclaredImpact? existing = await _dao.impactOf(_db, behaviorId);
    final AnchorEvidence? ev = await _dao.latestEvidence(_db, behaviorId);

    // 实测已经覆盖过，就不再接受新的先验：两套数并存会让明细页没法解释。
    if (existing != null && existing.isOverridden) {
      return (
        impact: null,
        verdict: TierChangeVerdict(
          ok: false,
          code: 'already_calibrated',
          message: '这一项已经被实测覆盖（${existing.replacedBy}）。'
              '先验不再改写——想改就看证据，或再测一次。',
        ),
      );
    }

    final TierChangeVerdict verdict = _engine.checkTierChange(
      to: tier,
      from: existing?.tier,
      hasCalibratedEvidence: ev != null,
      reason: reason,
    );
    if (!verdict.ok) {
      return (impact: null, verdict: verdict);
    }

    final DeclaredImpact impact = _engine.declare(
      behaviorId: behaviorId,
      tier: tier,
      source: source,
      at: at,
      note: reason,
    );
    await _dao.upsertImpact(_db, impact, now: at);
    return (impact: impact, verdict: verdict);
  }

  // ---------------------------------------------------------------- 写证据

  /// 记一次实测，并**在同一个事务里**把先验覆盖掉。
  ///
  /// 这就是规范里的 `CalibrationRule`：出现 calibrated 级证据 → 反算实际量级
  /// → 写 evidence → `DeclaredImpact.replacedBy` 指向它 → UI 显示
  /// "你当初估的是中偏大，实测接近中"。
  Future<AnchorEvidence> recordEvidence({
    required String behaviorId,
    required EvidenceKind kind,
    required double measuredValue,
    required String unit,
    required DateTime performedAt,
    String? rangeId,
    MeasurementClass measurementClass = MeasurementClass.formula,
    String note = '',
    String? id,
  }) async {
    final String evidenceId =
        id ?? 'ev_${performedAt.microsecondsSinceEpoch}_$behaviorId';
    final AnchorEvidence evidence = _engine.buildEvidence(
      id: evidenceId,
      behaviorId: behaviorId,
      kind: kind,
      measuredValue: measuredValue,
      unit: unit,
      performedAt: performedAt,
      range: rangeId == null ? null : referenceRangeById(rangeId),
      cls: measurementClass,
      note: note,
    );

    await _db.transaction<void>((Transaction txn) async {
      await _dao.insertEvidence(txn, evidence, now: DateTime.now());
      final DeclaredImpact? impact = await _dao.impactOf(txn, behaviorId);
      if (impact != null) {
        await _dao.upsertImpact(
          txn,
          _engine.coverWithEvidence(impact: impact, evidence: evidence),
          now: DateTime.now(),
        );
      }
    });
    return evidence;
  }

  /// 量级还没声明但已经有实测：补一条"证据档位"的先验，避免卡片半成品。
  Future<DeclaredImpact> adoptEvidenceAsPrior({
    required String behaviorId,
    required AnchorEvidence evidence,
    required DateTime at,
  }) async {
    final DeclaredImpact impact = _engine.declare(
      behaviorId: behaviorId,
      tier: evidence.derivedTier,
      source: ImpactSource.evidence,
      at: at,
      replaceEvidenceId: evidence.id,
      note: '由实测直接建立（${evidence.kind.label}）',
    );
    await _dao.upsertImpact(_db, impact, now: at);
    return impact;
  }

  // ---------------------------------------------------------------- 维护

  /// 只清刻度层。设置页的「清空全部数据」走 `MaintenanceRepository`，
  /// 那边按 `Tables.all` 遍历，已经包含这四张表。
  Future<void> clearLayer() async {
    await _db.transaction<void>((Transaction txn) async {
      await txn.delete(Tables.anchorEvidence);
      await txn.delete(Tables.declaredImpact);
      await txn.delete(Tables.anchorRevision);
      await txn.delete(Tables.userAnchor);
    });
  }
}
