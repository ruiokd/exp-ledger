/// 确认闭环仓储。
///
/// 系统不替用户断言"这件事真的发生了"。要做的是：
/// 把该问的问题排队、到点问、用户点头后落状态。
/// 同类型同一天同行为只排一次——反复弹同一个问题比不问更烦。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/confirmation_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/ids.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:sqflite/sqflite.dart';

class ConfirmationRepository {
  ConfirmationRepository({
    required AppDatabase database,
    DateTime Function()? clock,
  })  : _db = database.db,
        _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  final ConfirmationDao _tasks = const ConfirmationDao();

  /// 排队一个确认。已存在同键的 open 任务就跳过。
  Future<ConfirmationTask?> enqueue({
    required String kind,
    required String title,
    DayKey? day,
    String? behaviorCode,
    String detail = '',
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? dueAt,
  }) async {
    final exists = await _tasks.existsOpen(
      _db,
      kind: kind,
      day: day,
      behaviorCode: behaviorCode,
    );
    if (exists) return null;

    final now = _clock();
    final task = ConfirmationTask(
      id: newLocalId('cfm', now),
      kind: kind,
      title: title,
      createdAt: now,
      dayKey: day,
      behaviorCode: behaviorCode,
      detail: detail,
      payload: payload,
      dueAt: dueAt,
    );
    await _tasks.save(_db, task);
    return task;
  }

  Future<List<ConfirmationTask>> due() => _tasks.due(_db, _clock());

  Future<List<ConfirmationTask>> open({DayKey? day}) =>
      _tasks.open(_db, day: day);

  Future<bool> markDone(String id) async =>
      await _tasks.resolve(_db, id, 'done', at: _clock()) > 0;

  Future<bool> skip(String id) async =>
      await _tasks.resolve(_db, id, 'skipped', at: _clock()) > 0;

  Future<int> countOpen() => _tasks.countOpen(_db);

  Future<ConfirmationTask?> byId(String id) => _tasks.byId(_db, id);
}
