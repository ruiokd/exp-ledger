import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/science/acwr.dart';
import 'package:exp_ledger/domain/science/energy.dart';
import 'package:exp_ledger/domain/science/forgetting_curve.dart';
import 'package:exp_ledger/domain/science/s_rpe.dart';
import 'package:exp_ledger/domain/science/training_dose.dart';
import 'package:exp_ledger/domain/science/vo2max.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:test/test.dart';

const profile = UserProfile(
  weightKg: 72,
  heightCm: 172,
  age: 28,
  sex: Sex.male,
  restingHeartRate: 62,
);

void main() {
  group('热量：Mifflin-St Jeor', () {
    test('男 72kg / 172cm / 28 岁 → 1660 kcal', () {
      expect(bmrMifflinStJeor(profile), closeTo(1660, 0.01));
    });

    test('女性常数项为 −161，同等体格低 166 kcal', () {
      final female = profile.copyWith(sex: Sex.female);
      expect(
        bmrMifflinStJeor(profile) - bmrMifflinStJeor(female),
        closeTo(166, 0.01),
      );
    });

    test('异常输入不会产出负值或 NaN', () {
      const tiny = UserProfile(weightKg: 0, heightCm: 0, age: 200);
      final v = bmrMifflinStJeor(tiny);
      expect(v.isFinite, isTrue);
      expect(v, greaterThanOrEqualTo(800));
    });
  });

  group('热量：MET 与账本', () {
    test('MET 6.0 / 72kg / 2.2 分钟 → 16.63 kcal', () {
      expect(
        metKcal(met: 6.0, weightKg: 72, minutes: 2.2),
        closeTo(16.632, 0.001),
      );
    });

    test('时长为 0 时返回 0，不产生 NaN', () {
      expect(metKcal(met: 6, weightKg: 72, minutes: 0), 0);
    });

    test('一日账本的各项加总等于总消耗', () {
      final b = buildDailyBreakdown(
        profile: profile,
        intakeKcal: 2400,
        exerciseKcal: 400,
        activeDay: true,
      );
      expect(
        b.totalExpenditure,
        closeTo(b.bmr + b.tef + b.exercise + b.epoc + b.neat, 1e-9),
      );
      expect(b.tef, closeTo(240, 0.001));
      expect(b.epoc, closeTo(32, 0.001));
    });
  });

  group('训练剂量：有效组', () {
    test('1 组 12 次 RIR4 → 有效组 1.0', () {
      expect(
        effectiveSets(
            sets: 1, reps: 12, intensityFactor: 0.8, compensation: 1.0),
        closeTo(1.0, 1e-9),
      );
    });

    test('3 组 10 次 强度 0.9 → 3.375', () {
      expect(
        effectiveSets(
            sets: 3, reps: 10, intensityFactor: 0.9, compensation: 1.0),
        closeTo(3.375, 1e-9),
      );
    });

    test('次数很少时按一半兜底，不会归零', () {
      final v = effectiveSets(
          sets: 3, reps: 2, intensityFactor: 0.55, compensation: 0.65);
      expect(v, greaterThanOrEqualTo(1.5 - 1e-9));
    });

    test('RIR 越低强度系数越高，但封顶 1.0', () {
      expect(intensityFactorFromRir(0), 1.0);
      expect(intensityFactorFromRir(4), 0.8);
      expect(intensityFactorFromRir(10), 0.55);
    });

    test('Epley：100kg × 5 次 → 116.7；超过 12 次不外推', () {
      expect(epleyOneRm(weight: 100, reps: 5)!, closeTo(116.67, 0.01));
      expect(epleyOneRm(weight: 100, reps: 15), isNull);
    });
  });

  group('遗忘曲线：R = e^(−t/S)', () {
    test('S=7.82 天时，3 天后保持率约 68%', () {
      final s = memoryStrengthDays(activeRecallRatio: 0.85, priorExposures: 3);
      expect(s, closeTo(7.82, 0.02));
      expect(retention(hoursSinceStudy: 72, strengthDays: s),
          closeTo(0.682, 0.005));
    });

    test('只看一遍（0.2）的保持率显著低于主动回忆（0.85）', () {
      final passive = memoryStrengthDays(activeRecallRatio: 0.2, priorExposures: 1);
      final active = memoryStrengthDays(activeRecallRatio: 0.85, priorExposures: 1);
      expect(active, greaterThan(passive));
      expect(
        retention(hoursSinceStudy: 72, strengthDays: active),
        greaterThan(retention(hoursSinceStudy: 72, strengthDays: passive)),
      );
    });

    test('t=0 保持率为 1，t 增大单调下降', () {
      expect(retention(hoursSinceStudy: 0, strengthDays: 5), 1);
      final a = retention(hoursSinceStudy: 24, strengthDays: 5);
      final b = retention(hoursSinceStudy: 48, strengthDays: 5);
      expect(a, greaterThan(b));
    });

    test('反推保持率跌破 40% 的天数', () {
      final days = daysUntilRetentionBelow(target: 0.4, strengthDays: 5);
      expect(days, closeTo(5 * 0.9163, 0.01));
    });
  });

  group('session-RPE', () {
    test('RPE 8 × 60 分钟 = 480', () {
      expect(srpeLoad(rpe: 8, minutes: 60), 480);
    });

    test('RPE 输入越界会被夹紧到 0–10', () {
      expect(srpeLoad(rpe: 15, minutes: 60), 600);
      expect(srpeLoad(rpe: -3, minutes: 60), 0);
    });

    test('时长为 0 时不产生负荷', () {
      expect(srpeLoad(rpe: 10, minutes: 0), 0);
    });

    test('RIR 换算：RIR 2 ≈ RPE 8', () {
      expect(rpeFromRir(2), 8);
      expect(rpeFromRir(12), 0);
    });
  });

  group('ACWR 区间判定', () {
    const cfg = kDefaultConfig;
    final today = DayKey(2025, 6, 28);

    Map<DayKey, double> constant(double v, int days) => {
          for (var i = 0; i < days; i++) today.addDays(-i): v,
        };

    test('恒定负荷 → 比率 1.0 → 低风险', () {
      final r = computeAcwr(dailyLoads: constant(300, 28), today: today);
      expect(r.ratio, closeTo(1.0, 1e-9));
      expect(r.band, AcwrBand.low);
    });

    test('近 7 天猛增 → 比率 2.67 → 高风险', () {
      final loads = <DayKey, double>{
        for (var i = 0; i < 7; i++) today.addDays(-i): 600,
        for (var i = 7; i < 28; i++) today.addDays(-i): 100,
      };
      final r = computeAcwr(dailyLoads: loads, today: today);
      expect(r.ratio!, closeTo(2.6667, 0.01));
      expect(r.band, AcwrBand.high);
      expect(r.band.isRisk, isTrue);
    });

    test('近 7 天偏低 → 比率 0.4 → 去适应区间', () {
      final loads = <DayKey, double>{
        for (var i = 0; i < 7; i++) today.addDays(-i): 100,
        for (var i = 7; i < 28; i++) today.addDays(-i): 300,
      };
      final r = computeAcwr(dailyLoads: loads, today: today);
      expect(r.band, AcwrBand.underTrained);
      expect(acwrAdvice(r).contains('去训练'), isTrue);
    });

    test('边界：1.3 仍低风险，1.31 进警戒，1.51 进高风险', () {
      expect(bandFor(1.3), AcwrBand.low);
      expect(bandFor(1.31), AcwrBand.warning);
      expect(bandFor(1.5), AcwrBand.warning);
      expect(bandFor(1.51), AcwrBand.high);
      expect(bandFor(null), AcwrBand.low);
    });

    test('慢性负荷为 0 时比率无定义，而不是 0', () {
      final r = computeAcwr(dailyLoads: const {}, today: today);
      expect(r.ratio, isNull);
      expect(r.isDefined, isFalse);
      expect(acwrAdvice(r).contains('还不够'), isTrue);
    });

    test('高风险文案必须包含就医指引', () {
      final advice = acwrAdvice(const AcwrResult(
        acute7: 700,
        chronic28: 300,
        ratio: 2.0,
        band: AcwrBand.high,
        daysWithData: 28,
      ));
      expect(advice.contains('就医'), isTrue);
      expect(advice.contains('不做诊断'), isTrue);
    });
  });

  group('VO2max 估算', () {
    test('Uth–Sørensen：62 静息心率 → 合理区间', () {
      final v = vo2MaxFromHeartRate(age: 28, restingHr: 62)!;
      expect(v, greaterThan(40));
      expect(v, lessThan(60));
    });

    test('静息心率异常时返回 null 而不是瞎算', () {
      expect(vo2MaxFromHeartRate(age: 30, restingHr: 20), isNull);
    });

    test('Cooper 12 分钟：2400 米 → 约 42.4', () {
      expect(vo2MaxFromCooper(distanceMeters: 2400)!, closeTo(42.36, 0.05));
    });
  });
}
