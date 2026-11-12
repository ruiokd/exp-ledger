/// 数据库入口。
///
/// 只做四件事：定位文件、开库、跑迁移、关库。
/// 业务代码不要直接拿 `Database`——用仓储。
library;

import 'dart:async';

import 'package:exp_ledger/data/db/migrations.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;

  /// 实际文件路径（内存库为 `:memory:`）。
  final String path;

  static const String fileName = 'exp_ledger.db';

  /// 全局单例。UI 层只通过它拿数据库。
  static AppDatabase? _instance;

  static AppDatabase? get instanceOrNull => _instance;

  static AppDatabase get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('AppDatabase 还没初始化：先 await AppDatabase.open()');
    }
    return inst;
  }

  /// 打开（或复用）数据库。
  ///
  /// [path] 为空时落在系统数据库目录下的 `exp_ledger.db`。
  /// 测试传 `inMemoryDatabasePath` 即可拿到一次性的内存库。
  static Future<AppDatabase> open({String? path, bool singleton = true}) async {
    if (singleton && _instance != null) return _instance!;

    final resolved = path ??
        p.join(await getDatabasesPath(), fileName);

    final db = await openDatabase(
      resolved,
      version: Migrations.version,
      onConfigure: (Database db) async {
        // 并发写入时先等 5 秒再报 busy，比直接抛异常体验好。
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (Database db, int version) async {
        await Migrations.createAll(db);
      },
      onUpgrade: (Database db, int from, int to) async {
        await Migrations.upgrade(db, from: from, to: to);
      },
      onDowngrade: onDatabaseDowngradeDelete,
    );

    final inst = AppDatabase._(db, resolved);
    if (singleton) _instance = inst;
    return inst;
  }

  /// 一次性内存库，测试专用。
  static Future<AppDatabase> openInMemory() =>
      open(path: inMemoryDatabasePath, singleton: false);

  /// 只给维护功能用：逐表删数据，保留 schema。
  ///
  /// 注意：事务体内只能操作 `txn`。sqflite 里在事务中改用 `db` 会等自己
  /// 持有的锁，直接死锁——所以这里不调用 `Migrations.upgrade`。
  Future<void> wipeAll() async {
    await db.transaction((Transaction txn) async {
      for (final table in Tables.all) {
        await txn.delete(table);
      }
      // 清空后补回默认档案，保证 UI 读档案不空。
      await txn.insert(Tables.userProfile, <String, Object?>{
        'id': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> close() async {
    if (identical(_instance, this)) _instance = null;
    await db.close();
  }
}
