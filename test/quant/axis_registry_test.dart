/// 维度注册表：内置 5 维必须与 `ProjectAxis` / `decay_model` 保持一致。
library;

import 'package:exp_ledger/domain/forecast/decay_model.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/quant/axis_registry.dart';
import 'package:test/test.dart';

void main() {
  const AxisRegistry registry = AxisRegistry();

  group('内置维度与既有代码不漂', () {
    test('key 与 ProjectAxis 一一对应（顺序也一致）', () {
      expect(AxisRegistry.builtinKeys, AxisRegistry.projectAxisNames);
      expect(
        AxisRegistry.builtinKeys,
        ProjectAxis.values.map((ProjectAxis a) => a.name).toList(),
      );
    });

    test('label 与 ProjectAxis.label 一致', () {
      for (final ProjectAxis axis in ProjectAxis.values) {
        final AxisSpec? spec = registry.tryResolve(axis.name);
        expect(spec, isNotNull, reason: axis.name);
        expect(spec!.label, axis.label);
      }
    });

    test('衰减常数是 decay_model 的镜像（v1.2.1 会反过来查这张表）', () {
      for (final ProjectAxis axis in ProjectAxis.values) {
        expect(
          registry.tauFor(axis.name),
          detrainTau(axis),
          reason: '${axis.name} 的 tau 与 detrainTau 漂了',
        );
      }
    });

    test('内置维度全部是 ability', () {
      expect(registry.abilityAxes.length, 5);
      expect(registry.experienceAxes, isEmpty);
    });
  });

  group('未知维度不许静默变成某个内置维度', () {
    test('tryResolve 返回 null，而不是 strength', () {
      expect(registry.tryResolve('nope'), isNull);
      expect(registry.tryResolve(''), isNull);
    });

    test('resolve 落到 unknown（experience），不进能力曲线', () {
      final AxisSpec spec = registry.resolve('relation');
      expect(spec.key, AxisRegistry.unknown.key);
      expect(spec.isAbility, isFalse);
    });

    test('tauFor 未知维度按 30 天，体验维度恒 0', () {
      expect(registry.tauFor('nope'), 30);
      expect(
        registry.tauFor(AxisRegistry.unknown.key),
        0,
      );
    });

    test('isBuiltinKey 只认内置', () {
      expect(registry.isBuiltinKey('strength'), isTrue);
      expect(registry.isBuiltinKey('ua_1'), isFalse);
    });
  });

  group('用户维度', () {
    const AxisSpec relation = AxisSpec(
      key: 'ua_1',
      label: '关系',
      kind: AxisKind.ability,
      decayTauDays: 45,
      decayCitation: '陪伴停止后关系满意度回落较慢（经验近似）',
    );

    test('withUserAxes 返回新实例，不改原表', () {
      final AxisRegistry next = registry.withUserAxes(<AxisSpec>[relation]);
      expect(registry.tryResolve('ua_1'), isNull);
      expect(next.tryResolve('ua_1')?.label, '关系');
      expect(next.tryResolve('ua_1')?.isAbility, isTrue);
    });

    test('重复加入同一个 key 只保留一份', () {
      final AxisRegistry next = registry
          .withUserAxes(<AxisSpec>[relation])
          .withUserAxes(<AxisSpec>[relation]);
      expect(next.userAxes.length, 1);
    });

    test('不会用用户维度覆盖内置 key', () {
      const AxisSpec fakeStrength = AxisSpec(
        key: 'strength',
        label: '假体能',
        kind: AxisKind.experience,
      );
      final AxisRegistry next =
          registry.withUserAxes(<AxisSpec>[fakeStrength]);
      expect(next.tryResolve('strength')?.label, '体能');
      expect(next.userAxes, isEmpty);
    });

    test('体验维度的 tau 恒 0（没有能力可掉）', () {
      const AxisSpec exp = AxisSpec(
        key: 'ua_2',
        label: '情绪',
        kind: AxisKind.experience,
      );
      final AxisRegistry next = registry.withUserAxes(<AxisSpec>[exp]);
      expect(next.tauFor('ua_2'), 0);
    });

    test('newAxisKey 带 ua_ 前缀', () {
      expect(AxisRegistry.newAxisKey().startsWith('ua_'), isTrue);
    });
  });

  group('系数键映射（铁律 5：权重永远住在 BalanceConfig）', () {
    test('内置维度映射到 weightXxx', () {
      expect(registry.weightConfigKey('strength'), 'weightStrength');
      expect(registry.weightConfigKey('discipline'), 'weightRestraint');
    });

    test('用户维度映射到 axisWeight.<key>', () {
      expect(registry.weightConfigKey('ua_9'), 'axisWeight.ua_9');
    });
  });

  group('序列化', () {
    test('ability 维度带 tau，experience 维度不带', () {
      final Map<String, Object?> ability = const AxisSpec(
        key: 'ua_3',
        label: '体能储备',
        kind: AxisKind.ability,
        decayTauDays: 21,
      ).toJson();
      expect(ability['decay_tau_days'], 21);

      final Map<String, Object?> exp = const AxisSpec(
        key: 'ua_4',
        label: '审美',
        kind: AxisKind.experience,
      ).toJson();
      expect(exp.containsKey('decay_tau_days'), isFalse);
    });

    test('往返保持', () {
      const AxisSpec spec = AxisSpec(
        key: 'ua_5',
        label: '睡眠质量',
        kind: AxisKind.ability,
        decayTauDays: 9,
        decayCitation: '睡眠债经验近似',
      );
      final AxisSpec back = AxisSpec.fromJson(spec.toJson());
      expect(back.key, spec.key);
      expect(back.label, spec.label);
      expect(back.kind, spec.kind);
      expect(back.decayTauDays, spec.decayTauDays);
      expect(back.decayCitation, spec.decayCitation);
    });
  });
}
