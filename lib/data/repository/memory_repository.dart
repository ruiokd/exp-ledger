/// 记忆仓储：复习排程。
///
/// 间隔公式（全部系数来自 [BalanceConfig]，这里没有裸数字）：
///   interval = base × growth^reviewCount × boost
///   boost = 主动回忆 ? memoryActiveRecallBoost : memoryReviewBoost
/// 答错（recalled = false）→ 次数归零，间隔回到 base。
///
/// 这是"简单间隔重复"，不是 SM-2：单词量小、目标是不忘而不是应试，
/// 过度精细的难度因子收益有限。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/num_ext.dart';
import 'package:exp_ledger/data/dao/config_dao.dart';
import 'package:exp_ledger/data/dao/memory_item_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/ids.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite/sqflite.dart';

class MemoryRepository {
  MemoryRepository({required AppDatabase database, DateTime Function()? clock})
      : _db = database.db,
        _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  final MemoryItemDao _items = const MemoryItemDao();
  final ConfigDao _config = const ConfigDao();

  /// 加词。已存在就原样返回（不重置进度）。
  Future<MemoryItem> add(
    String word, {
    ProjectAxis axis = ProjectAxis.memory,
    double coverage = 0,
  }) async {
    final existing = await _items.byWord(_db, word);
    if (existing != null) return existing;

    final now = _clock();
    final config = await _config.effective(_db);
    final item = MemoryItem(
      id: newLocalId('mem', now),
      word: word,
      axis: axis,
      coverage: coverage.clampRange(0, 1),
      strength: _strengthOf(
        config,
        reviewCount: 0,
        activeRecall: true,
      ),
      nextReviewAt: now,
      createdAt: now,
    );
    await _items.save(_db, item);
    return item;
  }

  /// 批量加词。返回**实际新增**的词（已存在的不会重复出现）。
  Future<List<MemoryItem>> addMany(
    List<String> words, {
    ProjectAxis axis = ProjectAxis.memory,
    double coverage = 0,
  }) async {
    final added = <MemoryItem>[];
    for (final w in words) {
      final trimmed = w.trim();
      if (trimmed.isEmpty) continue;
      final before = await _items.byWord(_db, trimmed);
      if (before != null) continue;
      added.add(await add(trimmed, axis: axis, coverage: coverage));
    }
    return added;
  }

  Future<List<MemoryItem>> due({int limit = 50}) =>
      _items.due(_db, _clock(), limit: limit);

  Future<int> countDue() => _items.countDue(_db, _clock());

  Future<int> countAll() => _items.countAll(_db);

  /// 记一次复习。
  ///
  /// [recalled] 为 false 表示没想起来：间隔回到 base，但**不清零强度历史**，
  /// 下次答对会重新爬升——惩罚是"重新花时间"，不是"抹掉过去"。
  Future<MemoryItem> review(
    String word, {
    bool recalled = true,
    bool activeRecall = true,
    double coverage = 1,
  }) async {
    final existing = await _items.byWord(_db, word);
    final config = await _config.effective(_db);
    final now = _clock();

    final base = existing ??
        MemoryItem(
          id: newLocalId('mem', now),
          word: word,
          nextReviewAt: now,
          createdAt: now,
        );

    final nextCount = recalled ? base.reviewCount + 1 : 0;
    final intervalDays = _nextIntervalDays(
      config,
      reviewCount: nextCount,
      activeRecall: activeRecall,
    );

    final updated = MemoryItem(
      id: base.id,
      word: base.word,
      axis: base.axis,
      strength: intervalDays / _baseDays(config),
      coverage: recalled ? coverage.clampRange(0, 1) : 0,
      reviewCount: nextCount,
      activeRecall: activeRecall,
      lastReviewAt: now,
      nextReviewAt: now.add(Duration(days: intervalDays.round())),
      createdAt: base.createdAt,
    );
    await _items.save(_db, updated);
    return updated;
  }

  Future<bool> remove(String id) async => await _items.delete(_db, id) > 0;

  /// 强度 = 当前间隔 / 基准间隔（≥1）。量纲清楚，且完全由配置决定。
  double _strengthOf(
    BalanceConfig config, {
    required int reviewCount,
    required bool activeRecall,
  }) =>
      _nextIntervalDays(
        config,
        reviewCount: reviewCount,
        activeRecall: activeRecall,
      ) /
      _baseDays(config);

  double _baseDays(BalanceConfig config) =>
      config.memoryReviewBaseDays <= 0 ? 1.0 : config.memoryReviewBaseDays;

  /// 间隔天数。growth^count 用 `powSafe` 防溢出，最后夹到上限。
  double _nextIntervalDays(
    BalanceConfig config, {
    required int reviewCount,
    required bool activeRecall,
  }) {
    final base = _baseDays(config);
    final growth =
        config.memoryReviewGrowth <= 1 ? 1.0 : config.memoryReviewGrowth;
    final raw = base * powSafe(growth, reviewCount.toDouble());
    final boost =
        activeRecall ? config.memoryActiveRecallBoost : config.memoryReviewBoost;
    final value = raw * boost;
    final max = config.memoryReviewMaxDays <= base
        ? base
        : config.memoryReviewMaxDays;
    return value.clampRange(base, max).toDouble();
  }
}
