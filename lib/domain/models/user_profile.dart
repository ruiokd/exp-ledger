import '../enums.dart';

/// 用户基线档案。所有公式的个体化参数都从这里读。
///
/// 每个可校准字段都带一个 [Confidence]：用户随口填的是 selfReport，
/// 经 5 公里计时/1RM 测试反推的才是 calibrated。
class UserProfile {
  const UserProfile({
    this.heightCm = 172,
    this.weightKg = 70,
    this.age = 28,
    this.sex = Sex.male,
    this.restingHeartRate = 66,
    this.bodyFatPercent,
    this.sleepNeedHours = 7.5,
    this.sleepLine = const SleepLine(hour: 0, minute: 20),
    this.vocabularyEstimate = 6000,
    this.oneRmSquatKg,
    this.vo2MaxEstimate,
    this.profileConfidence = Confidence.selfReport,
    this.sleepConfidence = Confidence.selfReport,
    this.vo2Confidence = Confidence.selfReport,
    this.vocabConfidence = Confidence.selfReport,
    this.lastCalibratedAt,
  });

  final double heightCm;
  final double weightKg;
  final int age;
  final Sex sex;

  /// 静息心率（次/分）。用于 Uth–Sørensen 估算 VO2max。
  final int restingHeartRate;

  /// 体脂百分比，可选。缺省时不做瘦体重修正。
  final double? bodyFatPercent;

  /// 个人睡眠需求基准（小时）。默认 7.5，可由校准修正。
  final double sleepNeedHours;

  /// 个人"熬夜界线"：晚于此刻入睡即判定为熬夜。
  final SleepLine sleepLine;

  final int vocabularyEstimate;

  /// 深蹲 1RM（kg），由校准测试实测或 Epley 估算。
  final double? oneRmSquatKg;
  final double? vo2MaxEstimate;

  final Confidence profileConfidence;
  final Confidence sleepConfidence;
  final Confidence vo2Confidence;
  final Confidence vocabConfidence;
  final DateTime? lastCalibratedAt;

  /// 最弱的那个置信度，代表整个档案的可信上限。
  Confidence get overallConfidence => [
        profileConfidence,
        sleepConfidence,
        vo2Confidence,
        vocabConfidence,
      ].reduce(Confidence.min);

  /// 瘦体重（kg）。有体脂数据才计算，否则返回 null。
  double? get leanMassKg {
    final bf = bodyFatPercent;
    if (bf == null || bf <= 0 || bf >= 60) return null;
    return weightKg * (1 - bf / 100);
  }

  UserProfile copyWith({
    double? heightCm,
    double? weightKg,
    int? age,
    Sex? sex,
    int? restingHeartRate,
    double? bodyFatPercent,
    double? sleepNeedHours,
    SleepLine? sleepLine,
    int? vocabularyEstimate,
    double? oneRmSquatKg,
    double? vo2MaxEstimate,
    Confidence? profileConfidence,
    Confidence? sleepConfidence,
    Confidence? vo2Confidence,
    Confidence? vocabConfidence,
    DateTime? lastCalibratedAt,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      age: age ?? this.age,
      sex: sex ?? this.sex,
      restingHeartRate: restingHeartRate ?? this.restingHeartRate,
      bodyFatPercent: bodyFatPercent ?? this.bodyFatPercent,
      sleepNeedHours: sleepNeedHours ?? this.sleepNeedHours,
      sleepLine: sleepLine ?? this.sleepLine,
      vocabularyEstimate: vocabularyEstimate ?? this.vocabularyEstimate,
      oneRmSquatKg: oneRmSquatKg ?? this.oneRmSquatKg,
      vo2MaxEstimate: vo2MaxEstimate ?? this.vo2MaxEstimate,
      profileConfidence: profileConfidence ?? this.profileConfidence,
      sleepConfidence: sleepConfidence ?? this.sleepConfidence,
      vo2Confidence: vo2Confidence ?? this.vo2Confidence,
      vocabConfidence: vocabConfidence ?? this.vocabConfidence,
      lastCalibratedAt: lastCalibratedAt ?? this.lastCalibratedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'age': age,
        'sex': sex.name,
        'resting_hr': restingHeartRate,
        'body_fat': bodyFatPercent,
        'sleep_need_hours': sleepNeedHours,
        'sleep_line_hour': sleepLine.hour,
        'sleep_line_minute': sleepLine.minute,
        'vocabulary_estimate': vocabularyEstimate,
        'one_rm_squat': oneRmSquatKg,
        'vo2max_estimate': vo2MaxEstimate,
        'profile_confidence': profileConfidence.name,
        'sleep_confidence': sleepConfidence.name,
        'vo2_confidence': vo2Confidence.name,
        'vocab_confidence': vocabConfidence.name,
        'last_calibrated_at': lastCalibratedAt?.toIso8601String(),
      };
}

/// 个人熬夜界线。00:20 表示"晚于 00:20 入睡算熬夜"。
class SleepLine {
  const SleepLine({required this.hour, required this.minute});

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is SleepLine && other.totalMinutes == totalMinutes;

  @override
  int get hashCode => totalMinutes.hashCode;
}

/// 生理性别。仅用于 BMR 公式的常数项，不做其他推断。
enum Sex {
  male,
  female;

  double get bmrOffset => this == Sex.male ? 5 : -161;

  String get label => this == Sex.male ? '男' : '女';

  static Sex parse(String raw) =>
      Sex.values.firstWhere((e) => e.name == raw, orElse: () => Sex.male);
}
