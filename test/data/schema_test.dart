/// 第 4 步：schema 层验收。
///
/// 验的不是"代码能跑"，是"约束真的在库这一层生效"：
/// 唯一索引挡重复、部分唯一索引只挡主因、版本号对得上。
library;

import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/migrations.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> dailyRow({
    required String key,
    String day = '2025-06-01',
    String code = 'strength_training',
    String slot = 'main',
  }) {
    return <String, Object?>{
      'day_key': day,
      'behavior_code': code,
      'category': 'positive',
      'valence': 'positive',
      'axis': 'strength',
      'plan_status': 'planned',
      'confidence': 'selfReport',
      'slot_key': slot,
      'idempotency_key': key,
      'created_at': '${day}T19:00:00.000',
      'updated_at': '${day}T19:00:00.000',
    };
  }

  test('全部表都建好了', () async {
    for (final table in Tables.all) {
      expect(await tableExists(db, table), isTrue, reason: '缺表：$table');
    }
  });

  test('schema 版本等于 Migrations.version', () async {
    expect(await schemaVersion(db), Migrations.version);
  });

  test('默认档案已经塞好一行', () async {
    expect(await countRows(db, Tables.userProfile), 1);
  });

  test('关键索引存在', () async {
    const expected = <String>[
      Indexes.dailyLogIdempotency,
      Indexes.valenceSlot,
      Indexes.negativePrimary,
      Indexes.historyKey,
      Indexes.forecastDay,
      Indexes.memoryDue,
    ];
    for (final name in expected) {
      expect(await indexExists(db, name), isTrue, reason: '缺索引：$name');
    }
  });

  test('daily_log 的幂等键真的挡重复写入', () async {
    final row = dailyRow(key: '2025-06-01|strength_training|main');
    await db.db.insert(Tables.dailyLog, row);

    // 同一个幂等键再插一次 → 必须由数据库拒绝，而不是靠代码自觉。
    await expectLater(
      db.db.insert(Tables.dailyLog, row),
      throwsA(anything),
    );
    expect(await countRows(db, Tables.dailyLog), 1);
  });

  test('INSERT OR REPLACE 覆盖同一幂等键而不是新增一行', () async {
    final row = dailyRow(key: '2025-06-01|strength_training|main');
    await db.db.insert(Tables.dailyLog, row);
    await db.db.insert(
      Tables.dailyLog,
      <String, Object?>{
        ...row,
        'dose_fraction': 0.5,
        'revision': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    expect(await countRows(db, Tables.dailyLog), 1);
    final rows = await db.db.query(Tables.dailyLog);
    expect(rows.single['revision'], 1);
    expect((rows.single['dose_fraction'] as num).toDouble(), 0.5);
  });

  test('负向事件：同根因只允许一条主因', () async {
    Map<String, Object?> negative({required String code, required int primary}) {
      return <String, Object?>{
        'day_key': '2025-06-01',
        'behavior_code': code,
        'behavior_name': code,
        'dose_minutes': 90.0,
        'penalty_units': 0.5,
        'exp': -1.5,
        'root_cause_key': 'sleep@2025-06-01',
        'is_primary': primary,
      };
    }

    await db.db.insert(Tables.negativeEvent, negative(code: 'sleep', primary: 1));

    // 第二条主因、同根因 → 违反部分唯一索引。
    await expectLater(
      db.db.insert(
        Tables.negativeEvent,
        negative(code: 'sleep_again', primary: 1),
      ),
      throwsA(anything),
    );

    // 后果记录（is_primary = 0）可以有多条。
    await db.db.insert(
      Tables.negativeEvent,
      negative(code: 'absence', primary: 0),
    );
    await db.db.insert(
      Tables.negativeEvent,
      negative(code: 'absence_2', primary: 0),
    );
    expect(await countRows(db, Tables.negativeEvent), 3);
  });

  test('预测点主键是 (生成日, 轴, horizon)', () async {
    final row = <String, Object?>{
      'day_key': '2025-06-01',
      'axis': 'strength',
      'horizon_days': 3,
      'maintain': 41.0,
      'correct': 42.0,
      'low': 39.0,
      'high': 43.0,
      'confidence': 0.9,
      'is_projection': 1,
    };
    await db.db.insert(Tables.forecastPoint, row);
    await db.db.insert(
      Tables.forecastPoint,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    expect(await countRows(db, Tables.forecastPoint), 1);
  });
}
