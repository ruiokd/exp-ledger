/// 量化口径与自定义维度的**唯一写入口**。
///
/// 与 `AnchorRepository` 同一个位置、同一套纪律：
///   * 校验在前（`validateQuantSpec` 四道闸），过不了的**不写库**；
///   * 写库只走这里，DAO 只搬行；
///   * 日志不记用户自由文本（维度名、行为名都不进日志，只记 code 与计数）。
///
/// 它不参与结算：`SettlementPipeline` 拿不到这个仓储（preflight 4e 第 2 条）。
library;

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/data/dao/quant_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:sqflite/sqflite.dart';

class QuantRepository {
  QuantRepository({required AppDatabase database}) : _db = database.db;

  final Database _db;
  final QuantDao _dao = const QuantDao();

  /// 内置 5 维 + 库里启用的自定义维度。
  Future<AxisRegistry> registry() async => AxisRegistry(await _dao.axes(_db));

  Future<Map<String, QuantSpec>> specs() => _dao.specs(_db);

  Future<QuantSpec?> specFor(String code) => _dao.specByCode(_db, code);

  /// 保存一条口径。返回校验结果：`accepted == false` 时**库里什么都不会变**。
  Future<QuantValidation> save(QuantSpec spec) async {
    final AxisRegistry registry = await this.registry();
    final QuantValidation verdict =
        validateQuantSpec(spec, registry: registry);

    if (!verdict.accepted) {
      logWarn(
        'quant',
        '量化口径被拒',
        detail: 'code=${spec.behaviorCode} '
            'codes=${verdict.rejects.map((QuantIssue q) => q.code).join(",")}',
      );
      return verdict;
    }

    await _dao.upsertSpec(_db, verdict.spec, now: DateTime.now());
    logInfo(
      'quant',
      '保存量化口径',
      detail: 'code=${verdict.spec.behaviorCode} '
          'shape=${verdict.spec.shape.kind.name} '
          'measure=${verdict.spec.measureKind.name} '
          'axes=${verdict.spec.impact.length} '
          'ability=${verdict.spec.abilityShare > 0}',
    );
    return verdict;
  }

  /// 建一个自定义维度。被拒返回 null，原因只进日志 code（不记 label）。
  Future<AxisSpec?> createAxis({
    required String label,
    AxisKind kind = AxisKind.experience,
    double decayTauDays = 0,
    String decayCitation = '',
    DateTime? at,
  }) async {
    final String trimmed = label.trim();
    if (trimmed.isEmpty || trimmed.length > 12) {
      logWarn('quant', '维度被拒', detail: 'code=R_BAD_LABEL');
      return null;
    }
    if (kind == AxisKind.ability &&
        (decayTauDays <= 0 || decayCitation.trim().isEmpty)) {
      // 说不出"为什么掉这么慢"就不许进能力曲线（与 T_AXIS_DEMOTED 同一条规矩）。
      logWarn('quant', '维度被拒', detail: 'code=R_AXIS_NO_EVIDENCE');
      return null;
    }

    final DateTime now = at ?? DateTime.now();
    final AxisSpec axis = AxisSpec(
      key: AxisRegistry.newAxisKey(now),
      label: trimmed,
      kind: kind,
      decayTauDays: kind == AxisKind.ability ? decayTauDays : 0,
      decayCitation: kind == AxisKind.ability ? decayCitation.trim() : '',
    );
    await _dao.upsertAxis(_db, axis, now: now);
    logInfo('quant', '新建维度', detail: 'key=${axis.key} kind=${kind.name}');
    return axis;
  }

  /// 改一个自定义维度的量纲（升/降到 ability 时同样要求衰减依据）。
  Future<bool> updateAxis(AxisSpec axis) async {
    if (axis.key.isEmpty || axis.label.trim().isEmpty) return false;
    if (axis.isAbility &&
        (axis.decayTauDays <= 0 || axis.decayCitation.trim().isEmpty)) {
      logWarn('quant', '维度被拒', detail: 'code=R_AXIS_NO_EVIDENCE');
      return false;
    }
    await _dao.upsertAxis(_db, axis, now: DateTime.now());
    return true;
  }

  /// 删维度。**还有口径在用它就拒绝**：删掉之后那些口径会静默变成
  /// "未知维度 → 体验曲线"，用户会以为自己的项目丢了分。
  Future<bool> removeAxis(String key) async {
    final Map<String, QuantSpec> all = await specs();
    for (final QuantSpec spec in all.values) {
      for (final ImpactShare s in spec.impact) {
        if (s.axisKey == key) {
          logWarn('quant', '维度删除被拒', detail: 'key=$key code=${spec.behaviorCode}');
          return false;
        }
      }
    }
    await _dao.deleteAxis(_db, key);
    logInfo('quant', '删除维度', detail: 'key=$key');
    return true;
  }

  Future<void> removeSpec(String code) async {
    await _dao.deleteSpec(_db, code);
    logInfo('quant', '删除量化口径', detail: 'code=$code');
  }
}
