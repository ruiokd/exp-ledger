/// 版本化迁移。
///
/// 规则：
///   1. 已发布的版本对应的 DDL **永不修改**——只追加新版本。
///   2. 每次加字段都要同步 `Migrations.upgrade` 与 `Tables.all` 的导出逻辑。
///   3. 迁移必须幂等：同一个数据库被重复升级不会报错。
library;

import 'package:exp_ledger/data/db/schema.dart';
import 'package:sqflite/sqflite.dart';

class Migrations {
  const Migrations._();

  /// 当前 schema 版本。加迁移时 +1。
  static const int version = 3;

  /// 全新库：按 [kCreateStatements] 逐条建。
  static Future<void> createAll(Database db) async {
    for (final statement in kCreateStatements) {
      await db.execute(statement);
    }
    await _seedProfile(db);
  }

  /// 旧库升级。from < 2 / < 3 ... 逐段追加，不回头改老版本。
  static Future<void> upgrade(
    Database db, {
    required int from,
    required int to,
  }) async {
    // v1 → v2：新增 app_setting（提醒开关/时间）。
    // 用 IF NOT EXISTS，所以同一个库被重复升级不会炸。
    if (from < 2) {
      await db.execute(kAppSettingTable);
    }
    // v2 → v3：新增刻度标定层四张表（user_anchor / anchor_revision /
    // declared_impact / anchor_evidence）。全部 IF NOT EXISTS，重复升级不炸。
    // 既有 17 张表一行未改 —— 这一层是纯增量。
    if (from < 3) {
      for (final String statement in kAnchorTables) {
        await db.execute(statement);
      }
    }
    if (from < 1) {
      // 兜底：版本号被手工清过的库，直接补全。
      await createAll(db);
    }
  }

  /// 档案表只有一行（id = 1）。空库先塞一份默认档案，
  /// 这样任何页面读档案都不用处理「null」。
  static Future<void> _seedProfile(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${Tables.userProfile}',
    );
    final count = (rows.first['c'] as num?)?.toInt() ?? 0;
    if (count > 0) return;
    await db.insert(Tables.userProfile, <String, Object?>{
      'id': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
