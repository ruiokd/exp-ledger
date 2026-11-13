import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:test/test.dart';

/// 自建项目：提示词契约 + 解析校验 + 记录序列化。
/// 不测 derive（那是除法，且需要整套 DeriveContext），测"会不会写坏库"。
void main() {
  const AnchorConfig config = kDefaultAnchorConfig;

  group('提示词', () {
    final String text = NewBehaviorCodec.buildNewBehaviorRequestText(
      name: '上一堂课',
      description: '45 分钟的一节正课',
      config: config,
      expPerPoint: 0.5,
      axisHint: '我倾向：自律',
    );

    test('把项目名与四样要求写清楚', () {
      expect(text, contains('上一堂课'));
      expect(text, contains('45 分钟的一节正课'));
      expect(text, contains('target_dose'));
      expect(text, contains('axis'));
      expect(text, contains('category'));
    });

    test('沿用同一套档位纪律', () {
      expect(text, contains('不给数字'));
      expect(text, contains('large 我这边锁着'));
      expect(text, contains('没有 citation 会自动降一档'));
    });

    test('把量化公式交给 AI（计入比例 / 各轴权重 / EXP 点值）', () {
      expect(text, contains('实际量 ÷ target_dose'));
      expect(text, contains('0.50 EXP/点'));
      expect(text, contains('subjective'));
    });

    test('输出格式是单个 JSON 对象', () {
      expect(text, contains('"unit_label"'));
      expect(text, contains('"dose_unit"'));
      expect(text, contains('"tier": "small | medium | mediumHigh"'));
    });
  });

  group('解析', () {
    test('合规的一条通过', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '''
```json
{
  "name": "上一堂课",
  "description": "45 分钟的一节正课",
  "category": "positive",
  "axis": "discipline",
  "measurement_class": "formula",
  "unit_label": "一节课",
  "definition_text": "含讲与练、连续 45 分钟，中途打断超过 10 分钟按两节算",
  "target_dose": 45,
  "dose_unit": "分钟",
  "reference_range_id": "custom",
  "tier": "medium",
  "rationale": "占掉一段完整时间",
  "citation": "自定义"
}
```
''',
        config: config,
      );
      expect(r.error, isNull);
      final NewBehaviorProposal p = r.proposal!;
      expect(p.name, '上一堂课');
      expect(p.axis, ProjectAxis.discipline);
      expect(p.category, BehaviorCategory.positive);
      expect(p.targetDose, 45);
      expect(p.doseUnit, '分钟');
      expect(p.appliedTier, ImpactTier.medium);
      expect(p.downgraded, isFalse);
    });

    test('target_dose 缺失或 <= 0 → 打回（没有分母就算不出比例）', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","definition_text":"45 分钟",'
        '"tier":"medium","rationale":"占时间","citation":"x","target_dose":0}',
        config: config,
      );
      expect(r.proposal, isNull);
      expect(r.error, contains('target_dose'));
    });

    test('缺 definition_text → 打回', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","tier":"medium",'
        '"rationale":"占时间","citation":"x","target_dose":45}',
        config: config,
      );
      expect(r.proposal, isNull);
      expect(r.error, contains('definition_text'));
    });

    test('tier 给「大」→ 压到中偏大并说明', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","definition_text":"45 分钟",'
        '"tier":"large","rationale":"很占时间","citation":"经验","target_dose":45}',
        config: config,
      );
      final NewBehaviorProposal p = r.proposal!;
      expect(p.rawTier, ImpactTier.large);
      expect(p.appliedTier, ImpactTier.mediumHigh);
      expect(p.notes.join(), contains('只能由实测解锁'));
    });

    test('没有 citation → 降一档', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","definition_text":"45 分钟",'
        '"tier":"mediumHigh","rationale":"占掉整晚","citation":"","target_dose":45}',
        config: config,
      );
      final NewBehaviorProposal p = r.proposal!;
      expect(p.appliedTier, ImpactTier.medium);
      expect(p.notes.join(), contains('降到'));
    });

    test('自造数字档位 → 直接拒', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","definition_text":"45 分钟",'
        '"tier":"0.8","rationale":"算出来的","citation":"x","target_dose":45}',
        config: config,
      );
      expect(r.proposal, isNull);
      expect(r.error, contains('三档词表'));
    });

    test('未知参照区间退回 custom', () {
      final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
        '{"name":"上一堂课","unit_label":"一节","definition_text":"45 分钟",'
        '"tier":"medium","rationale":"占时间","citation":"x","target_dose":45,'
        '"reference_range_id":"不存在"}',
        config: config,
      );
      expect(r.proposal!.referenceRangeId, 'custom');
    });
  });

  group('记录', () {
    test('code 稳定且带前缀', () {
      final String code = customBehaviorCode(DateTime(2026, 5, 1));
      expect(code, startsWith('custom_'));
      expect(code, customBehaviorCode(DateTime(2026, 5, 1)));
    });

    test('序列化往返不丢字段', () {
      final CustomBehaviorRecord r = CustomBehaviorRecord(
        code: 'custom_1',
        name: '上一堂课',
        description: '45 分钟',
        category: BehaviorCategory.positive,
        axis: ProjectAxis.discipline,
        measurementClass: MeasurementClass.formula,
        unitLabel: '一节课',
        definitionText: '连续 45 分钟',
        targetDose: 45,
        doseUnit: '分钟',
        tier: ImpactTier.medium,
        createdAt: DateTime(2026, 5, 1),
      );
      final CustomBehaviorRecord back =
          CustomBehaviorRecord.fromJson(r.toJson());
      expect(back.code, r.code);
      expect(back.axis, r.axis);
      expect(back.measurementClass, MeasurementClass.formula);
      expect(back.targetDose, 45);
      expect(back.tier, ImpactTier.medium);
    });
  });
}
