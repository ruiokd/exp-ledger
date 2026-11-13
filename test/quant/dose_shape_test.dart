/// 量化形状的数值断言。
///
/// 三条不能破的约定（QUANT-PLUGIN.md 第八节）：
///   1. 所有形状在 `d == target` 处恒为 1.0 —— 满分线不随形状漂；
///   2. `0 < d < target` 区间严格单调不减 —— 多做不该少得分；
///   3. 半量处依次为 0.5 / 0.585 / 0.8 / 0 —— 有人"顺手优化"就会红。
library;

import 'package:exp_ledger/domain/quant/dose_shape.dart';
import 'package:test/test.dart';

void main() {
  const double t = 40; // 目标量 40 分钟，避免用 1 掩盖单位换算问题

  group('归一化：目标量处一律 1.0', () {
    for (final DoseShape shape in DoseShape.values) {
      test('${shape.name} 在 d == target 处为 1', () {
        final DoseShapeSpec spec = DoseShapeSpec(kind: shape);
        expect(spec.fractionFor(t, t), closeTo(1.0, 1e-6));
      });
    }

    test('阈值形状在 target * 0.5 处仍为 0', () {
      const DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.threshold);
      expect(spec.fractionFor(t * 0.5, t), 0);
    });
  });

  group('单调：0 < d < target 严格不减', () {
    for (final DoseShape shape in DoseShape.values) {
      test(shape.name, () {
        final DoseShapeSpec spec = DoseShapeSpec(kind: shape);
        double prev = -1;
        for (double d = 0; d <= t; d += t / 20) {
          final double x = spec.fractionFor(d, t);
          expect(x, greaterThanOrEqualTo(prev),
              reason: '${shape.name} 在 d=$d 处回落了');
          prev = x;
        }
      });
    }
  });

  group('半量处的分差（这一层的意义）', () {
    test('linear 0.5', () {
      expect(DoseShapeSpec(kind: DoseShape.linear).fractionFor(t * 0.5, t),
          closeTo(0.5, 1e-6));
    });

    test('log k=1 约 0.585', () {
      expect(DoseShapeSpec(kind: DoseShape.log).fractionFor(t * 0.5, t),
          closeTo(0.585, 1e-3));
    });

    test('saturating 0.8', () {
      expect(
        const DoseShapeSpec(kind: DoseShape.saturating).fractionFor(t * 0.5, t),
        closeTo(0.8, 1e-6),
      );
    });

    test('threshold 0', () {
      expect(const DoseShapeSpec(kind: DoseShape.threshold).fractionFor(t * 0.5, t),
          0);
    });
  });

  group('超额不在这里夹（交给 baseScoreFor 与效率加成）', () {
    test('linear 1.5 倍返回 1.5', () {
      expect(DoseShapeSpec(kind: DoseShape.linear).fractionFor(t * 1.5, t),
          closeTo(1.5, 1e-6));
    });

    test('saturating 1.5 倍不到 1.2', () {
      final double x =
          const DoseShapeSpec(kind: DoseShape.saturating).fractionFor(t * 1.5, t);
      expect(x, greaterThan(1.0));
      expect(x, lessThan(1.2));
    });
  });

  group('参数纪律', () {
    test('log 的非法 k 打回 R_FREE_PARAM', () {
      const DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.log, logK: 0.37);
      expect(spec.validate().accepted, isFalse);
      expect(spec.validate().code, 'R_FREE_PARAM');
    });

    test('log 的四档全部通过', () {
      for (final double k in DoseShapeSpec.allowedLogK) {
        final DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.log, logK: k);
        expect(spec.validate().accepted, isTrue, reason: 'k=$k');
      }
    });

    test('threshold 的绝对阈值（1.7 倍）打回', () {
      const DoseShapeSpec spec =
          DoseShapeSpec(kind: DoseShape.threshold, thetaFraction: 1.7);
      expect(spec.validate().accepted, isFalse);
    });

    test('非法 k 就近收敛，不抛异常（形状不影响力）', () {
      const DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.log, logK: 0.37);
      final double x = spec.fractionFor(t, t);
      expect(x, closeTo(1.0, 1e-6));
    });

    test('linear / saturating 不吃参数', () {
      const DoseShapeSpec linear =
          DoseShapeSpec(kind: DoseShape.linear, logK: 99, thetaFraction: 99);
      expect(linear.validate().accepted, isTrue);
      expect(linear.fractionFor(t * 0.5, t), closeTo(0.5, 1e-6));
    });
  });

  group('向后兼容与序列化', () {
    test('缺 shape 字段 = linear', () {
      final DoseShapeSpec spec = DoseShapeSpec.parseOrDefault(null);
      expect(spec.kind, DoseShape.linear);
      expect(spec.fractionFor(t * 0.25, t), closeTo(0.25, 1e-6));
    });

    test('未知形状名回落 linear，不静默变成别的形状', () {
      final DoseShapeSpec spec =
          DoseShapeSpec.parseOrDefault(<String, Object?>{'kind': 'biphasic'});
      expect(spec.kind, DoseShape.linear);
    });

    test('往返序列化保留 k 与 theta', () {
      const DoseShapeSpec logSpec = DoseShapeSpec(kind: DoseShape.log, logK: 2);
      expect(DoseShapeSpec.parseOrDefault(logSpec.toJson()).logK, 2);

      const DoseShapeSpec thSpec =
          DoseShapeSpec(kind: DoseShape.threshold, thetaFraction: 0.5);
      expect(
        DoseShapeSpec.parseOrDefault(thSpec.toJson()).thetaFraction,
        0.5,
      );
    });

    test('target 为 0 时退回 1，不产生 NaN/Infinity', () {
      final DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.log);
      final double x = spec.fractionFor(0, 0);
      expect(x.isNaN || x.isInfinite, isFalse);
      expect(x, 0);
    });

    test('尺度不变：同一比例在不同量级上结果相同', () {
      const DoseShapeSpec logSpec = DoseShapeSpec(kind: DoseShape.log, logK: 2);
      const DoseShapeSpec satSpec =
          DoseShapeSpec(kind: DoseShape.saturating);
      for (final double target in <double>[1, 40, 300, 0.5]) {
        expect(logSpec.fractionFor(target * 0.5, target),
            closeTo(0.631, 1e-3), reason: 'target=$target');
        expect(satSpec.fractionFor(target * 0.5, target),
            closeTo(0.8, 1e-6), reason: 'target=$target');
      }
    });

    test('log 的 k 越大，半量处越低（曲率确实在起作用）', () {
      final double halfK05 =
          DoseShapeSpec(kind: DoseShape.log, logK: 0.5).fractionFor(0.5, 1);
      final double halfK4 =
          DoseShapeSpec(kind: DoseShape.log, logK: 4).fractionFor(0.5, 1);
      expect(halfK05, closeTo(0.55, 1e-3));
      expect(halfK4, closeTo(0.683, 1e-3));
      expect(halfK4, greaterThan(halfK05));
    });

    test('负的 dose 夹到 0', () {
      final DoseShapeSpec spec = DoseShapeSpec(kind: DoseShape.linear);
      expect(spec.fractionFor(-5, t), 0);
    });
  });
}
