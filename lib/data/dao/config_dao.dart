/// `config_override` 读写。
///
/// 数值实验室改的系数落在这里（key → REAL）。
/// 读配置时先取默认值，再叠加覆盖值——**只有这里能改行为**，
/// 算法文件里永远不出现裸数字。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class ConfigDao {
  const ConfigDao();

  static const String table = Tables.configOverride;

  Future<Map<String, double>> loadOverrides(DatabaseExecutor db) async {
    final rows = await db.query(table);
    final out = <String, double>{};
    for (final r in rows) {
      final key = r['key']?.toString();
      if (key == null || key.isEmpty) continue;
      out[key] = asDouble(r['value']);
    }
    return out;
  }

  /// 只接受 [BalanceConfig.toMap] 里存在的键。
  /// 拼错的键直接忽略，否则会静默地"改了个不存在的系数"。
  Future<bool> setOverride(
    DatabaseExecutor db,
    String key,
    double value, {
    Map<String, double>? allowedKeys,
  }) async {
    final allowed = allowedKeys ?? kDefaultConfig.toMap();
    if (!allowed.containsKey(key)) return false;
    await db.insert(
      table,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  Future<int> removeOverride(DatabaseExecutor db, String key) => db.delete(
        table,
        where: 'key = ?',
        whereArgs: <Object?>[key],
      );

  Future<int> clear(DatabaseExecutor db) => db.delete(table);

  /// 默认值 + 覆盖值 = 生效配置。
  Future<BalanceConfig> effective(DatabaseExecutor db) async {
    final overrides = await loadOverrides(db);
    return kDefaultConfig.withOverrides(overrides);
  }
}
