/// 档案仓储：读 / 写基线，以及"一次校准怎么改档案"。
///
/// 校准是唯一会把 [Confidence] 从 selfReport 推到 calibrated 的途径——
/// 所以这里的每个分支都必须同时改值、改置信度、留一条校准记录。
library;

import 'package:exp_ledger/data/dao/calibration_dao.dart';
import 'package:exp_ledger/data/dao/user_profile_dao.dart';
import 'package:exp_ledger/data/db/app_database.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:sqflite/sqflite.dart';

class ProfileRepository {
  ProfileRepository({required AppDatabase database}) : _db = database.db;

  final Database _db;
  final UserProfileDao _profiles = const UserProfileDao();
  final CalibrationDao _calibrations = const CalibrationDao();

  Future<UserProfile> load() => _profiles.load(_db);

  Future<void> save(UserProfile profile) => _profiles.save(_db, profile);

  Future<List<CalibrationRecord>> recentCalibrations({int limit = 20}) =>
      _calibrations.recent(_db, limit: limit);

  /// 应用一次校准：写记录 + 改档案 + 提升对应字段的置信度。
  ///
  /// 未知 [CalibrationRecord.kind] 只落记录、不动档案——
  /// 宁可少改，也不要拿一个没定义的键去猜该改哪一列。
  Future<UserProfile> applyCalibration(CalibrationRecord record) async {
    await _calibrations.insert(_db, record);
    final current = await _profiles.load(_db);

    var next = current;
    final kind = record.kind;

    if (kind == 'vo2max_run' || kind == 'vo2max_test') {
      next = next.copyWith(
        vo2MaxEstimate: record.measuredValue,
        vo2Confidence: record.confidenceAfter,
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'one_rm_squat') {
      next = next.copyWith(
        oneRmSquatKg: record.measuredValue,
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'sleep_need') {
      next = next.copyWith(
        sleepNeedHours: record.measuredValue,
        sleepConfidence: record.confidenceAfter,
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'vocab_size') {
      next = next.copyWith(
        vocabularyEstimate: record.measuredValue.round(),
        vocabConfidence: record.confidenceAfter,
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'body_fat') {
      next = next.copyWith(
        bodyFatPercent: record.measuredValue,
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'resting_hr') {
      next = next.copyWith(
        restingHeartRate: record.measuredValue.round(),
        lastCalibratedAt: record.performedAt,
      );
    } else if (kind == 'profile') {
      next = next.copyWith(
        profileConfidence: record.confidenceAfter,
        lastCalibratedAt: record.performedAt,
      );
    }

    // 至少让"整个档案的可信上限"记得这次校准发生过。
    if (record.confidenceAfter.index > Confidence.selfReport.index &&
        identical(next, current)) {
      next = next.copyWith(profileConfidence: record.confidenceAfter);
    }

    await _profiles.save(_db, next);
    return next;
  }

  /// 哪个轴还没有任何实测校准。设置页用它提示"还有哪些可以测"。
  Future<Map<ProjectAxis, bool>> calibrationCoverage() async {
    final out = <ProjectAxis, bool>{};
    for (final axis in ProjectAxis.values) {
      out[axis] = await _calibrations.countForAxis(_db, axis) > 0;
    }
    return out;
  }
}
