/// 只在数据层存在的模型。
///
/// 它们不参与算法（算法层不需要知道"校准记录有几条""徽章叫什么"），
/// 所以不放进 `domain/`——domain 保持纯算法，数据层自己管自己的形状。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';

/// 一次校准。用来支撑"从自报变实测"这件事有据可查。
class CalibrationRecord {
  const CalibrationRecord({
    required this.id,
    required this.kind,
    required this.axis,
    required this.measuredValue,
    required this.unit,
    required this.source,
    required this.confidenceBefore,
    required this.confidenceAfter,
    required this.performedAt,
    this.raw = const <String, Object?>{},
    this.createdAt,
  });

  final String id;

  /// 校准类型：`vo2max_run` / `one_rm_squat` / `sleep_need` / `vocab_size`。
  final String kind;
  final ProjectAxis axis;

  /// 实测值（原始单位，不换算）。
  final double measuredValue;
  final String unit;

  /// 怎么测出来的：`5k_time` / `epley` / `app_test` / `manual`。
  final String source;

  final Confidence confidenceBefore;
  final Confidence confidenceAfter;

  final DateTime performedAt;

  /// 原始输入（用时、次数、重量……），便于事后复算。
  final Map<String, Object?> raw;

  final DateTime? createdAt;
}

/// 一个待复习的词。间隔由 [BalanceConfig] 的 memoryReview* 系数决定。
class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.word,
    required this.nextReviewAt,
    required this.createdAt,
    this.axis = ProjectAxis.memory,
    this.strength = 1,
    this.coverage = 0,
    this.reviewCount = 0,
    this.activeRecall = true,
    this.lastReviewAt,
  });

  final String id;
  final String word;
  final ProjectAxis axis;

  /// 记忆强度（越大越牢）。1 = 刚学。
  final double strength;

  /// 覆盖度 0–1：这个词在最近一次测试里是否被正确复述。
  final double coverage;

  final int reviewCount;

  /// 是否用主动回忆（而非重读）复习。主动回忆的增益更高。
  final bool activeRecall;

  final DateTime? lastReviewAt;
  final DateTime nextReviewAt;
  final DateTime createdAt;
}

/// 确认任务：把"用户说做了"变成"系统问一句，用户点头"。
class ConfirmationTask {
  const ConfirmationTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.dayKey,
    this.behaviorCode,
    this.detail = '',
    this.status = 'open',
    this.payload = const <String, Object?>{},
    this.dueAt,
    this.resolvedAt,
  });

  final String id;

  /// `next_day` / `calibration` / `symptom_followup`。
  final String kind;
  final String title;

  final DayKey? dayKey;
  final String? behaviorCode;

  final String detail;

  /// `open` / `done` / `skipped` / `expired`。
  final String status;

  final Map<String, Object?> payload;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get isOpen => status == 'open';
}

/// 徽章。只记录"发生过"，不做排行榜、不做连续天数威胁。
class Badge {
  const Badge({
    required this.id,
    required this.code,
    required this.title,
    required this.earnedAt,
    this.detail = '',
    this.dayKey,
  });

  final String id;
  final String code;
  final String title;
  final String detail;
  final DayKey? dayKey;
  final DateTime earnedAt;
}
