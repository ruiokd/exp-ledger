/// `user_profile` 读写。
///
/// 表里恒为一行（`id = 1`）。迁移时会先塞一份默认值，
/// 所以 [load] 永远有东西返回，UI 不需要处理 null。
library;

import 'package:exp_ledger/data/db/json_cols.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:sqflite/sqflite.dart';

class UserProfileDao {
  const UserProfileDao();

  static const String table = Tables.userProfile;
  static const int rowId = 1;

  Future<UserProfile> load(DatabaseExecutor db) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[rowId],
      limit: 1,
    );
    if (rows.isEmpty) return const UserProfile();
    return fromRow(rows.first);
  }

  Future<void> save(DatabaseExecutor db, UserProfile p) async {
    await db.insert(
      table,
      toRow(p),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> toRow(UserProfile p) => <String, Object?>{
        'id': rowId,
        'height_cm': p.heightCm,
        'weight_kg': p.weightKg,
        'age': p.age,
        'sex': p.sex.name,
        'resting_hr': p.restingHeartRate,
        'body_fat': p.bodyFatPercent,
        'sleep_need_hours': p.sleepNeedHours,
        'sleep_line_hour': p.sleepLine.hour,
        'sleep_line_minute': p.sleepLine.minute,
        'vocabulary_estimate': p.vocabularyEstimate,
        'one_rm_squat': p.oneRmSquatKg,
        'vo2max_estimate': p.vo2MaxEstimate,
        'profile_confidence': p.profileConfidence.name,
        'sleep_confidence': p.sleepConfidence.name,
        'vo2_confidence': p.vo2Confidence.name,
        'vocab_confidence': p.vocabConfidence.name,
        'last_calibrated_at': p.lastCalibratedAt?.toIso8601String(),
        'updated_at': nowIso(),
      };

  UserProfile fromRow(Map<String, Object?> r) => UserProfile(
        heightCm: asDouble(r['height_cm'], fallback: 172),
        weightKg: asDouble(r['weight_kg'], fallback: 70),
        age: asInt(r['age'], fallback: 28),
        sex: Sex.parse(r['sex']?.toString() ?? 'male'),
        restingHeartRate: asInt(r['resting_hr'], fallback: 66),
        bodyFatPercent: asDoubleOrNull(r['body_fat']),
        sleepNeedHours: asDouble(r['sleep_need_hours'], fallback: 7.5),
        sleepLine: SleepLine(
          hour: asInt(r['sleep_line_hour']),
          minute: asInt(r['sleep_line_minute'], fallback: 20),
        ),
        vocabularyEstimate: asInt(r['vocabulary_estimate'], fallback: 6000),
        oneRmSquatKg: asDoubleOrNull(r['one_rm_squat']),
        vo2MaxEstimate: asDoubleOrNull(r['vo2max_estimate']),
        profileConfidence: Confidence.parse(
          r['profile_confidence']?.toString() ?? 'selfReport',
        ),
        sleepConfidence: Confidence.parse(
          r['sleep_confidence']?.toString() ?? 'selfReport',
        ),
        vo2Confidence: Confidence.parse(
          r['vo2_confidence']?.toString() ?? 'selfReport',
        ),
        vocabConfidence: Confidence.parse(
          r['vocab_confidence']?.toString() ?? 'selfReport',
        ),
        lastCalibratedAt: parseDate(r['last_calibrated_at']),
      );
}
