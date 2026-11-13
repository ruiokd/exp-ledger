import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:test/test.dart';

void main() {
  const AnchorConfig config = kDefaultAnchorConfig;
  const AnchorEngine engine = AnchorEngine();

  const List<ProposalTarget> targets = <ProposalTarget>[
    ProposalTarget(
      behaviorId: 'mind.deepTalk',
      label: '和重要的人深谈',
      measurementClass: MeasurementClass.subjective,
      rangeIds: <String>['deep_conversation', 'custom'],
    ),
    ProposalTarget(
      behaviorId: 'strength.session',
      label: '力量训练',
      measurementClass: MeasurementClass.formula,
      rangeIds: <String>['strength_sets'],
    ),
  ];

  group('导出：给网页 AI 的请求文本', () {
    final String text = AnchorProposalCodec.buildRequestText(
      targets: targets,
      config: config,
      expPerPoint: 0.5,
      extraContext: '我在备考，晚上通常只剩一小时',
    );

    test('带上「禁止自由数字」和「大被锁」两条硬约束', () {
      expect(text, contains('不许给数字'));
      expect(text, contains('large 我这边锁着'));
    });

    test('把我们的量化公式写给 AI（档位权重 + 置信权重 + EXP）', () {
      expect(text, contains('50%'));
      expect(text, contains('0.6'));
      // toStringAsFixed(2) → 「0.50 EXP/点」
      expect(text, contains('0.50 EXP/点'));
    });

    test('只暴露允许引用的参照区间', () {
      expect(text, contains('`strength_sets`'));
      expect(text, contains('`deep_conversation`'));
      expect(text, isNot(contains('`passive_scroll`')));
    });

    test('输出格式是 JSON 数组，字段齐全', () {
      expect(text, contains('"unit_label"'));
      expect(text, contains('"definition_text"'));
      expect(text, contains('"rationale"'));
      expect(text, contains('"citation"'));
    });

    test('补上用户上下文', () {
      expect(text, contains('我在备考'));
    });
  });

  group('导入：从 AI 回复里抠 JSON', () {
    test('剥掉 ```json 围栏与前后废话', () {
      const String raw = '''
好的，我按你的规则处理了：

```json
[{"behavior_id":"strength.session"}]
```

需要我调整哪一条就说。
''';
      expect(AnchorProposalCodec.extractJson(raw),
          contains('"behavior_id":"strength.session"'));
    });

    test('字符串里的括号不影响配对', () {
      const String raw =
          '前言 [{"behavior_id":"a","rationale":"包含 ] 和 } 也不截断"}] 尾巴';
      final String? json = AnchorProposalCodec.extractJson(raw);
      expect(json, isNotNull);
      expect(json, endsWith('}]'));
    });

    test('完全没有 JSON → R_NOT_JSON', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '我觉得都挺重要的，你自己定吧。',
        targets: targets,
        config: config,
      );
      expect(b.accepted, isEmpty);
      expect(b.rejected.single.code, 'R_NOT_JSON');
    });
  });

  group('导入：逐条校验', () {
    test('合规的一条原样通过', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "mind.deepTalk",
  "unit_label": "一次深谈",
  "definition_text": "不被打断、超过 20 分钟、聊的是感受而不是安排",
  "reference_object": "相当于独自散步 30 分钟的恢复量",
  "reference_range_id": "deep_conversation",
  "tier": "medium",
  "rationale": "20 分钟以上会挤掉当晚别的事",
  "citation": "deep_conversation 参照区间"
}]
''',
        targets: targets,
        config: config,
      );
      expect(b.rejected, isEmpty);
      final AiProposal p = b.accepted.single;
      expect(p.appliedTier, ImpactTier.medium);
      expect(p.downgraded, isFalse);
      expect(p.notes, isEmpty);
    });

    test('AI 想给「大」→ 压到中偏大并留一条说明', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
{"items":[{
  "behavior_id": "strength.session",
  "unit_label": "一次训练",
  "definition_text": "含至少 3 个主项各 3 组",
  "reference_range_id": "strength_sets",
  "tier": "large",
  "rationale": "量很大",
  "citation": "训练经验"
}]}
''',
        targets: targets,
        config: config,
      );
      final AiProposal p = b.accepted.single;
      expect(p.rawTier, ImpactTier.large);
      expect(p.appliedTier, ImpactTier.mediumHigh);
      expect(p.downgraded, isTrue);
      expect(p.notes.join(), contains('只能由实测解锁'));
    });

    test('没有 citation → 自动降一档', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "mind.deepTalk",
  "unit_label": "一次深谈",
  "definition_text": "超过 20 分钟且不被打断",
  "tier": "mediumHigh",
  "rationale": "会占掉当晚大部分精力",
  "citation": ""
}]
''',
        targets: targets,
        config: config,
      );
      final AiProposal p = b.accepted.single;
      expect(p.rawTier, ImpactTier.mediumHigh);
      expect(p.appliedTier, ImpactTier.medium);
      expect(p.notes.join(), contains('降一档'));
    });

    test('自造数字档位 → R_FREE_NUMBER', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "mind.deepTalk",
  "unit_label": "一次深谈",
  "definition_text": "超过 20 分钟",
  "tier": "0.8",
  "rationale": "综合权重 0.8",
  "citation": "我算的"
}]
''',
        targets: targets,
        config: config,
      );
      expect(b.accepted, isEmpty);
      expect(b.rejected.single.code, 'R_FREE_NUMBER');
    });

    test('缺 definition_text → 打回（没法判断算不算一次）', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "mind.deepTalk",
  "unit_label": "一次深谈",
  "tier": "medium",
  "rationale": "挺重要",
  "citation": "经验"
}]
''',
        targets: targets,
        config: config,
      );
      expect(b.rejected.single.code, 'R_NO_DEFINITION');
    });

    test('缺 rationale → 打回（不可审计）', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "mind.deepTalk",
  "unit_label": "一次深谈",
  "definition_text": "超过 20 分钟",
  "tier": "medium",
  "citation": "经验"
}]
''',
        targets: targets,
        config: config,
      );
      expect(b.rejected.single.code, 'R_NO_RATIONALE');
    });

    test('不在本次清单里的行为 → R_UNKNOWN_BEHAVIOR', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[{
  "behavior_id": "gaming.rank",
  "unit_label": "一局",
  "definition_text": "打一局排位",
  "tier": "medium",
  "rationale": "很投入",
  "citation": "经验"
}]
''',
        targets: targets,
        config: config,
      );
      expect(b.rejected.single.code, 'R_UNKNOWN_BEHAVIOR');
    });

    test('混批：好的进、坏的拦，各自带序号', () {
      final ProposalBundle b = AnchorProposalCodec.decode(
        '''
[
 {"behavior_id":"strength.session","unit_label":"一次训练",
  "definition_text":"3 个主项各 3 组","reference_range_id":"strength_sets",
  "tier":"medium","rationale":"两个主项以上","citation":"区间"},
 {"behavior_id":"nope","unit_label":"x","definition_text":"y",
  "tier":"medium","rationale":"z","citation":"c"},
 {"behavior_id":"mind.deepTalk","unit_label":"一次深谈",
  "definition_text":"20 分钟以上不被打断","tier":"medium",
  "rationale":"会挤掉别的事","citation":"区间"}
]
''',
        targets: targets,
        config: config,
      );
      expect(b.rawItemCount, 3);
      expect(b.accepted.length, 2);
      expect(b.rejected.length, 1);
      expect(b.rejected.single.index, 1);
      expect(b.summary, contains('3 条'));
    });
  });

  group('确认路径', () {
    test('确认后的提案走和手填完全相同的先验路径', () {
      final AiProposal p = AiProposal(
        behaviorId: 'mind.deepTalk',
        unitLabel: '一次深谈',
        definitionText: '超过 20 分钟且不被打断',
        referenceObject: '',
        referenceRangeId: 'deep_conversation',
        rawTier: ImpactTier.medium,
        appliedTier: ImpactTier.medium,
        rationale: '会挤掉别的事',
        citation: '区间',
      );
      final DeclaredImpact impact = AnchorProposalCodec.toDeclaredImpact(
        proposal: p,
        engine: engine,
        at: DateTime(2026, 5, 1),
      );
      expect(impact.source, ImpactSource.userPrior);
      expect(impact.weight, config.tierMediumPrior);
      expect(impact.note, contains('AI 提议，已确认'));
      expect(impact.replacedBy, isNull);
    });
  });

  group('配置不可越界', () {
    test('withOverrides 改不动封顶语义', () {
      final AnchorConfig tuned =
          config.withOverrides(<String, double>{'tierMediumPrior': 0.9});
      final double w = AnchorEngine(tuned).priorWeightFor(
        tier: ImpactTier.medium,
        source: ImpactSource.userPrior,
      );
      expect(w, 0.5, reason: '调高单项也必须被 priorWeightCap 夹住');
    });

    test('toMap 的键与字段一一对应（实验室白名单）', () {
      final Map<String, double> map = config.toMap();
      expect(map['priorWeightCap'], 0.5);
      expect(map['aiProposalDiscount'], lessThan(1.0));
      expect(map.length, greaterThanOrEqualTo(18));
    });
  });
}
