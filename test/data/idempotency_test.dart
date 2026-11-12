/// 第 4 步验收（一）：幂等写入。
///
/// 这里**不接** SettlementRepository——只验写库这一层的语义：
/// 同键覆盖、修订归档、内容不变就什么都不做。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/daily_log_history_dao.dart';
import 'package:exp_ledger/data/dao/dirty_day_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/repository/capture_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;
  late CaptureRepository capture;
  final day = DayKey(2025, 6, 1);

  setUp(() async {
    db = await openTestDb();
    capture = CaptureRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('同一个幂等键写两次只留一行，且第二次是 unchanged', () async {
    final first = await capture.commit(positiveDraft(day: day));
    expect(first.action, CommitAction.inserted);
    expect(first.entry.revision, 0);

    final second = await capture.commit(positiveDraft(day: day));
    expect(second.action, CommitAction.unchanged);
    expect(second.needsRecompute, isFalse);

    expect(await countRows(db, Tables.dailyLog), 1);
    expect(await countRows(db, Tables.dailyLogHistory), 0);
  });

  test('内容不变时不标脏：重复提交不会触发重算', () async {
    await capture.commit(positiveDraft(day: day));
    final dirty = const DirtyDayDao();
    await dirty.clearAll(db.db);
    expect(await dirty.count(db.db), 0);

    await capture.commit(positiveDraft(day: day));
    expect(await dirty.count(db.db), 0, reason: 'unchanged 不应标脏');
  });

  test('改剂量 → 覆盖同一行，旧版本进历史表，revision +1', () async {
    await capture.commit(positiveDraft(day: day, dose: 0.3));
    final revised = await capture.commit(positiveDraft(day: day, dose: 1.0));

    expect(revised.action, CommitAction.revised);
    expect(revised.entry.revision, 1);
    expect(await countRows(db, Tables.dailyLog), 1);

    final history = await const DailyLogHistoryDao().versionsOf(
      db.db,
      '${day.iso}|strength_training|main',
    );
    expect(history.length, 1);
    expect(history.first['revision'], 0);
    expect(
      (history.first['dose_fraction'] as num).toDouble(),
      0.3,
      reason: '历史里留的是被覆盖前的值',
    );
  });

  test('同一天同行为不同槽位 = 两条记录', () async {
    await capture.commit(positiveDraft(day: day, slot: 'squat'));
    await capture.commit(positiveDraft(day: day, slot: 'bench'));
    expect(await countRows(db, Tables.dailyLog), 2);
  });

  test('同槽位不同行为 = 两条记录', () async {
    await capture.commit(positiveDraft(day: day, code: 'strength_training'));
    await capture.commit(positiveDraft(day: day, code: 'cardio_run'));
    expect(await countRows(db, Tables.dailyLog), 2);
  });

  test('幂等键格式是 dayKey|behaviorCode|slotKey', () async {
    final entry = positiveDraft(day: day, slot: 'main');
    expect(entry.idempotencyKey, '2025-06-01|strength_training|main');

    // 先落库才能读回来——上一版这里漏了 commit，读的是空表。
    await capture.commit(entry);
    final stored = await capture.forDay(day);
    expect(stored.single.idempotencyKey, entry.idempotencyKey);
  });

  test('撤销会删行、留档、标脏', () async {
    await capture.commit(positiveDraft(day: day));
    final removed = await capture.undo(
      day,
      behaviorCode: 'strength_training',
      slotKey: 'main',
    );

    expect(removed, isTrue);
    expect(await countRows(db, Tables.dailyLog), 0);
    expect(await countRows(db, Tables.dailyLogHistory), 1);
    expect(await const DirtyDayDao().count(db.db), 1);
  });

  test('撤销不存在的记录返回 false，不产生脏日', () async {
    final removed = await capture.undo(
      day,
      behaviorCode: 'strength_training',
    );
    expect(removed, isFalse);
    expect(await const DirtyDayDao().count(db.db), 0);
  });

  test('"同上一次"能读到最近一次的答案', () async {
    await capture.commit(positiveDraft(day: day));
    final answers = await capture.lastAnswers('strength_training');
    expect(answers, isNotNull);
    expect(answers!['sets'], 4);
  });

  test('内容比较与键序无关', () async {
    final a = positiveDraft(day: day).copyWith(
      answers: <String, Object?>{'sets': 4, 'rir': 2},
    );
    final b = positiveDraft(day: day).copyWith(
      answers: <String, Object?>{'rir': 2, 'sets': 4},
    );
    await capture.commit(a);
    final second = await capture.commit(b);
    expect(second.action, CommitAction.unchanged);
  });
}
