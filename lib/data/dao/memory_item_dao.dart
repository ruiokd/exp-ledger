/// `memory_item` 读写。
///
/// 复习间隔的算法不在这里——这里只存 `next_review_at`。
/// 间隔由 [MemoryRepository] 用 BalanceConfig 的 memoryReview* 系数算，
/// 保证"数值实验室改系数 → 复习节奏跟着变"。
library;

import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class MemoryItemDao {
  const MemoryItemDao();

  static const String table = Tables.memoryItem;

  Future<void> save(DatabaseExecutor db, MemoryItem m) async {
    await db.insert(
      table,
      toRow(m),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveMany(DatabaseExecutor db, List<MemoryItem> items) async {
    if (items.isEmpty) return;
    final batch = db.batch();
    for (final m in items) {
      batch.insert(
        table,
        toRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<MemoryItem?> byId(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  Future<MemoryItem?> byWord(DatabaseExecutor db, String word) async {
    final rows = await db.query(
      table,
      where: 'word = ?',
      whereArgs: <Object?>[word],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return fromRow(rows.first);
  }

  /// 到期该复习的词。[now] 由调用方传入，便于测试固定时钟。
  Future<List<MemoryItem>> due(
    DatabaseExecutor db,
    DateTime now, {
    int limit = 50,
  }) async {
    final rows = await db.query(
      table,
      where: 'next_review_at <= ?',
      whereArgs: <Object?>[now.toIso8601String()],
      orderBy: 'next_review_at ASC',
      limit: limit,
    );
    return rows.map(fromRow).toList();
  }

  Future<int> countDue(DatabaseExecutor db, DateTime now) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE next_review_at <= ?',
      <Object?>[now.toIso8601String()],
    );
    return asInt(rows.first['c']);
  }

  Future<int> countAll(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return asInt(rows.first['c']);
  }

  Future<int> delete(DatabaseExecutor db, String id) => db.delete(
        table,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );

  Map<String, Object?> toRow(MemoryItem m) => <String, Object?>{
        'id': m.id,
        'word': m.word,
        'axis': m.axis.name,
        'strength': m.strength,
        'coverage': m.coverage,
        'review_count': m.reviewCount,
        'active_recall': boolToInt(m.activeRecall),
        'last_review_at': m.lastReviewAt?.toIso8601String(),
        'next_review_at': m.nextReviewAt.toIso8601String(),
        'created_at': m.createdAt.toIso8601String(),
      };

  MemoryItem fromRow(Map<String, Object?> r) => MemoryItem(
        id: r['id']?.toString() ?? '',
        word: r['word']?.toString() ?? '',
        axis: ProjectAxis.parse(r['axis']?.toString() ?? 'memory'),
        strength: asDouble(r['strength'], fallback: 1),
        coverage: asDouble(r['coverage']),
        reviewCount: asInt(r['review_count']),
        activeRecall: asBool(r['active_recall'], fallback: true),
        lastReviewAt: parseDate(r['last_review_at']),
        nextReviewAt: parseDate(r['next_review_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        createdAt: parseDate(r['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
