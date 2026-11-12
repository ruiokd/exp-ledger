/// 配置仓储：数值实验室的唯一落点。
///
/// 读：默认值 + 覆盖值 → 生效配置。
/// 写：只允许写 [BalanceConfig.toMap] 里存在的键（拼错的键会被拒绝）。
/// 改完由调用方触发 `SettlementRepository.recomputeFrom()`——
/// 系数变了，整条曲线必须跟着重算，否则图表和配置会互相打脸。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/data/dao/config_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:sqflite/sqflite.dart';

/// 一次写入的结果。
class ConfigWriteResult {
  const ConfigWriteResult({required this.ok, required this.key, this.message});

  final bool ok;
  final String key;
  final String? message;
}

class ConfigRepository {
  ConfigRepository({required AppDatabase database}) : _db = database.db;

  final Database _db;
  final ConfigDao _config = const ConfigDao();

  /// 生效配置。
  Future<BalanceConfig> effective() => _config.effective(_db);

  Future<Map<String, double>> overrides() => _config.loadOverrides(_db);

  /// 默认值（未覆盖）与生效值的对照表。数值实验室的列表页用它。
  Future<Map<String, ({double current, double baseline})>> diff() async {
    final current = await effective();
    final baseline = kDefaultConfig.toMap();
    final now = current.toMap();
    final out = <String, ({double current, double baseline})>{};
    for (final entry in baseline.entries) {
      out[entry.key] = (
        current: now[entry.key] ?? entry.value,
        baseline: entry.value,
      );
    }
    return out;
  }

  Future<ConfigWriteResult> set(String key, double value) async {
    if (!value.isFinite) {
      return ConfigWriteResult(ok: false, key: key, message: '不是有限数');
    }
    final accepted = await _config.setOverride(_db, key, value);
    if (!accepted) {
      return ConfigWriteResult(
        ok: false,
        key: key,
        message: '没有这个系数：$key',
      );
    }
    return ConfigWriteResult(ok: true, key: key);
  }

  Future<ConfigWriteResult> setMany(Map<String, double> values) async {
    for (final entry in values.entries) {
      final r = await set(entry.key, entry.value);
      if (!r.ok) return r;
    }
    return const ConfigWriteResult(ok: true, key: '*');
  }

  Future<void> reset(String key) => _config.removeOverride(_db, key);

  Future<void> resetAll() => _config.clear(_db);
}
