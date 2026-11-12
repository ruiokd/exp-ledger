/// 数据层测试的公共脚手架。
///
/// 关键是让 sqflite 走 ffi 实现：这样 `flutter test` 里就能开真 SQLite，
/// 不用模拟器、不用文件、每个用例一个内存库。
library;

import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/dao/config_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/repository/capture_repository.dart';
import 'package:exp_ledger/data/repository/settlement_repository.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 打开一个一次性的内存库。调用方负责 [AppDatabase.close]。
Future<AppDatabase> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return AppDatabase.openInMemory();
}

/// 固定时钟：所有重算都以这一天为"今天"，
/// 否则测试会随真实日期漂移（比如跨年那天跑就挂了）。
final DateTime kTestNow = DateTime(2025, 6, 3, 12);

/// 造一条正向训练记录。[dose] 直接决定基础分，用来测"改历史值曲线跟着变"。
DraftEntry positiveDraft({
  required DayKey day,
  double dose = 1.0,
  String slot = 'main',
  String code = 'strength_training',
  ProjectAxis axis = ProjectAxis.strength,
  Map<String, double> metrics = const <String, double>{
    'sets': 4,
    'rir': 2,
    'session_minutes': 40,
  },
}) {
  return DraftEntry(
    dayKey: day,
    behaviorCode: code,
    category: BehaviorCategory.positive,
    valence: Valence.positive,
    axis: axis,
    planStatus: PlanStatus.planned,
    confidence: Confidence.selfReport,
    slotKey: slot,
    answers: <String, Object?>{'sets': 4, 'rir': 2},
    metrics: metrics,
    interpretation: '训练：4 组，RIR 2',
    doseFraction: dose,
    source: 'manual',
    createdAt: day.startOfDay.add(const Duration(hours: 19)),
  );
}

/// 造一条"熬夜"负向记录。[minutes] 是越界分钟数。
DraftEntry lateNightDraft({
  required DayKey day,
  double minutes = 90,
  String slot = 'sleep',
}) {
  return DraftEntry(
    dayKey: day,
    behaviorCode: 'sleep_deprivation',
    category: BehaviorCategory.negative,
    valence: Valence.negative,
    axis: ProjectAxis.discipline,
    planStatus: PlanStatus.offPlan,
    confidence: Confidence.selfReport,
    slotKey: slot,
    answers: const <String, Object?>{},
    metrics: <String, double>{'late_minutes': minutes},
    interpretation: '熬夜 90 分钟',
    doseFraction: 1,
    source: 'manual',
    createdAt: day.startOfDay.add(const Duration(hours: 1)),
  );
}

/// 造一条触发安全闸的记录（关键词命中「胸闷」）。
DraftEntry redFlagDraft({required DayKey day}) {
  return DraftEntry(
    dayKey: day,
    behaviorCode: 'strength_training',
    category: BehaviorCategory.positive,
    valence: Valence.positive,
    axis: ProjectAxis.strength,
    planStatus: PlanStatus.planned,
    confidence: Confidence.selfReport,
    slotKey: 'flag',
    answers: const <String, Object?>{'note': '训练时胸闷'},
    metrics: const <String, double>{'session_minutes': 30},
    interpretation: '训练时胸闷，停了',
    doseFraction: 0.2,
    source: 'manual',
    createdAt: day.startOfDay.add(const Duration(hours: 18)),
  );
}

/// 一次把库、仓储装好。测试里九成情况用这个。
///
/// 一个 rig 只共享**一个** [SettlementRepository]：它内部有串行锁，
/// 建两个实例等于绕开锁，并发用例会互相删产物。
class TestRig {
  TestRig._(this.database, this.settlement, this.capture);

  factory TestRig(AppDatabase database) {
    final settlement = SettlementRepository(
      database: database,
      clock: () => kTestNow,
    );
    final capture = CaptureRepository(
      database: database,
      settlement: settlement,
    );
    return TestRig._(database, settlement, capture);
  }

  final AppDatabase database;
  final SettlementRepository settlement;
  final CaptureRepository capture;

  ConfigDao get configDao => const ConfigDao();

  Future<void> close() => database.close();
}

/// 直接查某表行数，绕过 DAO——测试要验的是库里的真实状态。
Future<int> countRows(AppDatabase db, String table) async {
  final rows = await db.db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

/// 索引是否存在。
Future<bool> indexExists(AppDatabase db, String name) async {
  final rows = await db.db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
    <Object?>[name],
  );
  return rows.isNotEmpty;
}

/// 表是否存在。
Future<bool> tableExists(AppDatabase db, String name) async {
  final rows = await db.db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object?>[name],
  );
  return rows.isNotEmpty;
}

/// 当前 schema 版本。
Future<int> schemaVersion(AppDatabase db) async {
  final rows = await db.db.rawQuery('PRAGMA user_version');
  return (rows.first.values.first as num?)?.toInt() ?? 0;
}

/// 表名清单导出给断言用。
List<String> get allTableNames => Tables.all;
