/// 数据库入口。
///
/// 只做四件事：定位文件、开库、跑迁移、关库。
/// 业务代码不要直接拿 `Database`——用仓储。
library;

import 'dart:async';
import 'dart:developer' as developer;

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
      onConfigure: _applyPragmas,
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

  /// 开库前的会话级设置（`onConfigure` 回调）。
  ///
  /// **必须走 `rawQuery`，绝不能走 `execute`。** sqflite 的 `execute` 在 Android 上
  /// 落到 `SQLiteDatabase.execSQL`，而 Android 14（API 34）起 execSQL 会拒绝
  /// "可能返回结果集"的语句——PRAGMA 正在其中，于是抛：
  ///
  ///   DatabaseException(unknown error (code 0 SQLITE_OK):
  ///   Queries can be performed using SQLiteDatabase query or rawQuery methods only.)
  ///
  /// 这条异常发生在 `onConfigure`，也就是**开库阶段**，会直接把 `runApp` 之前的
  /// boot 打断：v1.0.1 在 Android 14 上第一次打开就是它（v1.0.0 的黑屏同源，
  /// 只是那时没有诊断页，用户只看到一屏黑）。一条性能调优语句不该有能力拦住启动，
  /// 所以这里还吞异常：失败就退回默认 busy_timeout（0，撞锁立刻报错），功能不受影响。
  ///
  /// 写库里的任何语句同理：`execute` 只用来跑没有结果集的 DDL / DML，
  /// `PRAGMA`、`SELECT`、`EXPLAIN` 一律 `rawQuery`。
  static Future<void> _applyPragmas(Database db) async {
    const List<String> pragmas = <String>[
      // 并发写入时先等 5 秒再报 busy，比直接抛异常体验好。
      'PRAGMA busy_timeout = 5000',
    ];
    for (final String sql in pragmas) {
      try {
        // 用 rawQuery 拿到并丢弃结果集；sqflite 会自己关游标。
        await db.rawQuery(sql);
      } catch (error) {
        developer.log('PRAGMA 未生效，继续启动：$sql',
            name: 'AppDatabase', error: error);
      }
    }
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
