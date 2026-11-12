/// 开库路径的回归测试。
///
/// 这一组是被线上事故逼出来的：v1.0.1 在 Android 14 上一启动就停在诊断页，
///
///   DatabaseException(unknown error (code 0 SQLITE_OK):
///   Queries can be performed using SQLiteDatabase query or rawQuery methods only.)
///   sql 'PRAGMA busy_timeout = 5000'
///
/// 原因是 `onConfigure` 里用 `db.execute()` 跑 PRAGMA，而 Android 14 的
/// `SQLiteDatabase.execSQL` 拒绝可能返回结果集的语句。
///
/// 陷阱在于**测试环境复现不了它**：ffi 实现不经过 Java 的 execSQL，
/// `execute('PRAGMA ...')` 在 ffi 上照样"成功"。所以这里除了行为断言，
/// 还要一条读源码的静态断言——把"execute 跑 PRAGMA"这种写法挡在门外，
/// 而不是指望测试跑出异常。preflight.sh 里也有一条同样的 grep。
library;

import 'dart:io';

import 'package:exp_ledger/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  test('开库走通，且 busy_timeout 生效', () async {
    final AppDatabase db = await openTestDb();
    addTearDown(db.close);

    final List<Map<String, Object?>> rows =
        await db.db.rawQuery('PRAGMA busy_timeout');
    expect(rows, hasLength(1));
    expect(rows.first.values.first, 5000);
  });

  test('源码里不许用 execute 跑 PRAGMA（Android 14 会拒绝）', () {
    final String source =
        File('lib/data/db/app_database.dart').readAsStringSync();

    // 允许的写法：rawQuery('PRAGMA ...')
    expect(source.contains("execute('PRAGMA"), isFalse,
        reason: 'onConfigure 里的 PRAGMA 必须走 rawQuery；'
            'execute 落到 execSQL，Android 14+ 抛 '
            '"Queries can be performed using SQLiteDatabase query or rawQuery methods only."');
  });
}
