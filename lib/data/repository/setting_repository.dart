/// 应用设置读写（`app_setting`）。
///
/// 和 `config_override` 的区别：
///   - `config_override` 只放**算法系数**，有白名单，改了就重算；
///   - `app_setting` 放**用户偏好**（提醒开关、提醒时间），不参与结算。
///
/// 混在一张表里会让"改了个设置把曲线重算了"这种事发生。
library;

import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class SettingRepository {
  SettingRepository({required AppDatabase database}) : _db = database.db;

  final Database _db;

  static const String table = Tables.appSetting;

  // ---- 已知键（写死在这里，拼错会在编译期被发现）----

  /// '1' / '0'
  static const String reminderEnabled = 'reminder_enabled';

  /// 0–23
  static const String reminderHour = 'reminder_hour';

  /// 0–59
  static const String reminderMinute = 'reminder_minute';

  Future<String?> read(String key) async {
    final rows = await _db.query(
      table,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> write(String key, String value) async {
    await _db.insert(
      table,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> readBool(String key, {bool fallback = false}) async {
    final raw = await read(key);
    if (raw == null) return fallback;
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  Future<void> writeBool(String key, bool value) =>
      write(key, value ? '1' : '0');

  Future<int> readInt(String key, {int fallback = 0}) async {
    final raw = await read(key);
    if (raw == null) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  Future<void> writeInt(String key, int value) => write(key, '$value');

  Future<int> remove(String key) => _db.delete(
        table,
        where: 'key = ?',
        whereArgs: <Object?>[key],
      );

  Future<Map<String, String>> all() async {
    final rows = await _db.query(table);
    final out = <String, String>{};
    for (final row in rows) {
      final key = row['key']?.toString();
      if (key == null) continue;
      out[key] = row['value']?.toString() ?? '';
    }
    return out;
  }
}
