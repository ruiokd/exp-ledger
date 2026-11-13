/// 采集写入口。
///
/// **全系统唯一能写 `daily_log` 的地方。** 别处想存一条记录，
/// 只能构造 [DraftEntry] 调 [CaptureRepository.commit]。
///
/// 为什么死守这一个口子：
///   1. 幂等键只有在这里生成，重复提交才不会变成两条；
///   2. 脏日标记只有在这里打，级联重算才不会漏；
///   3. 修订链只有在这里归档，历史才可追。
library;

import 'dart:convert';

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/capture_session_dao.dart';
import 'package:exp_ledger/data/dao/daily_log_dao.dart';
import 'package:exp_ledger/data/dao/daily_log_history_dao.dart';
import 'package:exp_ledger/data/dao/dirty_day_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/repository/settlement_repository.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:sqflite/sqflite.dart';

/// 一次提交发生了什么。
enum CommitAction {
  /// 新写入。
  inserted,

  /// 覆盖了同一幂等键的旧记录（旧版本已归档）。
  revised,

  /// 内容与库里完全一致，什么都没做（**不会**触发重算）。
  unchanged;

  String get label {
    if (this == CommitAction.inserted) return '已记录';
    if (this == CommitAction.revised) return '已修正';
    return '内容未变';
  }
}

class CommitResult {
  const CommitResult({
    required this.entry,
    required this.action,
    this.dirtyFrom,
  });

  final DraftEntry entry;
  final CommitAction action;

  /// 需要重算的起始日。未变更时为 null。
  final DayKey? dirtyFrom;

  bool get changed => action != CommitAction.unchanged;

  bool get needsRecompute => dirtyFrom != null;
}

class CaptureRepository {
  CaptureRepository({
    required AppDatabase database,
    SettlementRepository? settlement,
  })  : _db = database.db,
        _settlement = settlement;

  final Database _db;

  /// 可选：给了就在写入后自动跑级联重算。
  /// 测试里可以只测写入、单独测重算，互不干扰。
  final SettlementRepository? _settlement;

  final DailyLogDao _daily = const DailyLogDao();
  final DailyLogHistoryDao _history = const DailyLogHistoryDao();
  final DirtyDayDao _dirty = const DirtyDayDao();
  final CaptureSessionDao _sessions = const CaptureSessionDao();

  /// 写入一条记录。
  ///
  /// 幂等键 = `dayKey|behaviorCode|slotKey`：
  ///   - 库里没有 → 插入；
  ///   - 有且内容相同 → 什么都不做（不标脏、不重算）；
  ///   - 有但内容不同 → 旧行归档进 history，新行 revision + 1。
  Future<CommitResult> commit(DraftEntry entry) async {
    final result = await _db.transaction<CommitResult>(
      (Transaction txn) async {
        final existing = await _daily.byIdempotencyKey(txn, entry.idempotencyKey);

        if (existing != null && _sameContent(existing, entry)) {
          return CommitResult(
            entry: existing,
            action: CommitAction.unchanged,
          );
        }

        if (existing != null) {
          final oldRow = await _daily.rawByKey(txn, entry.idempotencyKey);
          if (oldRow != null) {
            await _history.archive(txn, oldRow);
          }
          final revised = entry.copyWith(revision: existing.revision + 1);
          await _daily.replace(txn, revised);
          await _dirty.mark(txn, revised.dayKey, reason: 'revise');
          return CommitResult(
            entry: revised,
            action: CommitAction.revised,
            dirtyFrom: revised.dayKey,
          );
        }

        await _daily.insert(txn, entry);
        await _dirty.mark(txn, entry.dayKey, reason: 'write');
        return CommitResult(
          entry: entry,
          action: CommitAction.inserted,
          dirtyFrom: entry.dayKey,
        );
      },
    );

    // 只记「什么操作、什么结果」——答案和数值不进日志（日志会被复制出去）。
    logInfo(
      'capture',
      '${result.action.name} ${result.entry.behaviorCode}',
      detail: 'day=${result.entry.dayKey.iso} '
          'conf=${result.entry.confidence.name} '
          'recompute=${result.needsRecompute}',
    );

    if (result.needsRecompute) {
      // 重算必须在事务外——sqflite 不支持嵌套事务。
      try {
        await _settlement?.recomputeFrom(result.dirtyFrom!);
      } catch (error, stack) {
        logError('settle', '写入后重算失败', error: error, stack: stack);
        rethrow;
      }
    }
    return result;
  }

  /// 撤销一条录入。删行 + 归档 + 标脏，然后重算。
  Future<bool> undo(DayKey day, {required String behaviorCode, String slotKey = ''}) async {
    final key = '${day.iso}|$behaviorCode|$slotKey';
    final removed = await _db.transaction<int>((Transaction txn) async {
      final row = await _daily.rawByKey(txn, key);
      if (row == null) return 0;
      await _history.archive(txn, row);
      final n = await _daily.deleteByIdempotencyKey(txn, key);
      if (n > 0) await _dirty.mark(txn, day, reason: 'undo');
      return n;
    });
    if (removed > 0) {
      await _settlement?.recomputeFrom(day);
    }
    return removed > 0;
  }

  Future<List<DraftEntry>> forDay(DayKey day) => _daily.byDay(_db, day);

  Future<List<DraftEntry>> recent({int days = 14, DayKey? through}) {
    final end = through ?? DayKey.today();
    return _daily.between(_db, end.addDays(-(days - 1)), end);
  }

  Future<List<DraftEntry>> between(DayKey from, DayKey to) =>
      _daily.between(_db, from, to);

  /// "同上一次"用。
  Future<Map<String, Object?>?> lastAnswers(String behaviorCode) =>
      _daily.lastAnswers(_db, behaviorCode);

  Future<Set<String>> behaviorCodesOn(DayKey day) =>
      _daily.behaviorCodesOn(_db, day);

  Future<List<Map<String, Object?>>> versionHistory(String idempotencyKey) =>
      _history.versionsOf(_db, idempotencyKey);

  Future<void> saveSession(CaptureSession session) =>
      _sessions.save(_db, session);

  /// 内容是否等价。
  ///
  /// 比较的是**会影响结算结果**的字段，不是整行：`updated_at`
  /// 每次都变，`revision` 由这里维护，两者都不参与比较。
  bool _sameContent(DraftEntry a, DraftEntry b) {
    if (a.behaviorCode != b.behaviorCode) return false;
    if (a.category != b.category) return false;
    if (a.valence != b.valence) return false;
    if (a.axis != b.axis) return false;
    if (a.planStatus != b.planStatus) return false;
    if (a.confidence != b.confidence) return false;
    if (a.slotKey != b.slotKey) return false;
    if (a.isInterruption != b.isInterruption) return false;
    if (a.interpretation != b.interpretation) return false;
    if ((a.doseFraction - b.doseFraction).abs() > 1e-9) return false;
    if (_canonical(a.answers) != _canonical(b.answers)) return false;
    if (_canonical(a.metrics) != _canonical(b.metrics)) return false;
    if (_canonical(a.notes) != _canonical(b.notes)) return false;
    return true;
  }

  /// 稳定 JSON：键排序后编码。否则 `{a:1,b:2}` 与 `{b:2,a:1}` 会被判成不同。
  String _canonical(Object? value) => jsonEncode(_sortDeep(value));

  Object? _sortDeep(Object? value) {
    if (value is Map) {
      final keys = value.keys.map<String>((Object? k) => '$k').toList()..sort();
      final out = <String, Object?>{};
      for (final k in keys) {
        out[k] = _sortDeep(value[k]);
      }
      return out;
    }
    if (value is List) {
      return value.map<Object?>((Object? v) => _sortDeep(v)).toList();
    }
    return value;
  }
}
