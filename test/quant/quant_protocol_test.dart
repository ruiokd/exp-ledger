/// 离线提案协议（`quant_request` + `quant_response` 两端）：
/// 导出的文本要说得清，导入的回复要一条一条过闸。
library;

import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:test/test.dart';

const AxisRegistry registry = AxisRegistry();

const String happyJson = '''
好的，这是结果：
```json
{
  "items": [
    {
      "behavior_code": "custom_film",
      "measure": { "kind": "episode", "unit": "次", "how_to_check": "看没看完片尾字幕" },
      "shape": { "kind": "threshold", "theta_fraction": 1 },
      "target_dose": 1,
      "impact": [
        { "axis": "relation", "axis_label": "关系", "dim_kind": "experience", "share": 1.0 }
      ],
      "rationale": "看电影是事件而不是剂量",
      "citation": "事件型行为按发生/未发生二值计"
    },
    {
      "behavior_code": "custom_reading",
      "measure": { "kind": "duration_min", "unit": "分钟" },
      "shape": { "kind": "log", "k": 2 },
      "target_dose": 30,
      "impact": [ { "axis": "writing", "dim_kind": "ability", "share": 1.0 } ],
      "rationale": "前 20 分钟最有效"
    }
  ]
}
```
''';

void main() {
  group('导出：请求文本', () {
    final String text = buildQuantRequestText(
      targets: const <QuantRequestTarget>[
        QuantRequestTarget(
          code: 'custom_film',
          name: '看一场电影',
          definition: '从片头到片尾，中途不刷手机',
          targetDose: 1,
          doseUnit: '次',
        ),
      ],
      registry: registry,
      appVersion: '1.1.4',
    );

    test('包含四种形状与档位', () {
      expect(text, contains('linear'));
      expect(text, contains('saturating'));
      expect(text, contains('threshold'));
      expect(text, contains('0.5 / 1 / 2 / 4'));
    });

    test('包含内置维度与行为码', () {
      expect(text, contains('`strength`'));
      expect(text, contains('custom_film'));
      expect(text, contains('看一场电影'));
    });

    test('明确禁止自由数字', () {
      expect(text, contains('不要输出公式'));
      expect(text, contains('decay_citation'));
    });

    test('空注册表也照样能出文本（不会崩）', () {
      final String t = buildQuantRequestText(
        targets: const <QuantRequestTarget>[
          QuantRequestTarget(code: 'x', name: 'x'),
        ],
      );
      expect(t.contains('## 五'), isTrue);
    });
  });

  group('导入：好的一条条进', () {
    final QuantDecodeResult result = decodeQuantResponse(happyJson, registry: registry);

    test('两条都收下', () {
      expect(result.acceptedCount, 2, reason: result.rejected.toString());
      expect(result.rejectedCount, 0);
      expect(result.batchIssues, isEmpty);
    });

    test('身份是 aiProposal（确认后才变 userPrior）', () {
      for (final QuantValidation v in result.accepted) {
        expect(v.spec.source, 'aiProposal');
      }
    });

    test('事件型那条走 threshold，量 1 次算满', () {
      final QuantSpec film = result.accepted
          .firstWhere((QuantValidation v) => v.spec.behaviorCode == 'custom_film')
          .spec;
      expect(film.shape.kind, DoseShape.threshold);
      expect(film.doseFractionFor(1), 1);
      expect(film.contributesExp, isFalse, reason: 'experience 维度不该产生 EXP');
    });

    test('对数那条保留 k=2，标签从注册表补齐', () {
      final QuantSpec reading = result.accepted
          .firstWhere((QuantValidation v) =>
              v.spec.behaviorCode == 'custom_reading')
          .spec;
      expect(reading.shape.kind, DoseShape.log);
      expect(reading.shape.logK, 2);
      expect(reading.impact.single.axisLabel, '写作');
      expect(reading.contributesExp, isTrue);
    });

    test('没有 citation 时记「无」而不是空串', () {
      final QuantSpec reading = result.accepted
          .firstWhere((QuantValidation v) =>
              v.spec.behaviorCode == 'custom_reading')
          .spec;
      expect(reading.citation, '无');
    });
  });

  group('导入：坏的一条条打回，带序号', () {
    QuantDecodeResult run(String json) => decodeQuantResponse(json, registry: registry);

    test('形状不在白名单 → R_UNKNOWN_SHAPE', () {
      final QuantDecodeResult r = run('''
{"items":[{"behavior_code":"c1","measure":{"kind":"duration_min","unit":"分钟"},
"shape":{"kind":"biphasic"},"target_dose":30,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]}
''');
      expect(r.rejectedCount, 1);
      expect(
        r.rejected.single.issues.map((QuantIssue q) => q.code),
        contains('R_UNKNOWN_SHAPE'),
      );
    });

    test('k=0.37 → R_FREE_PARAM', () {
      final QuantDecodeResult r = run('''
{"items":[{"behavior_code":"c1","measure":{"kind":"duration_min","unit":"分钟"},
"shape":{"kind":"log","k":0.37},"target_dose":30,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]}
''');
      expect(
        r.rejected.single.issues.map((QuantIssue q) => q.code),
        contains('R_FREE_PARAM'),
      );
    });

    test('缺单位 → R_NO_UNIT', () {
      final QuantDecodeResult r = run('''
{"items":[{"behavior_code":"c1","measure":{"kind":"count"},
"shape":{"kind":"linear"},"target_dose":10,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]}
''');
      expect(
        r.rejected.single.issues.map((QuantIssue q) => q.code),
        contains('R_NO_UNIT'),
      );
    });

    test('量法不认识 → R_UNKNOWN_MEASURE', () {
      final QuantDecodeResult r = run('''
{"items":[{"behavior_code":"c1","measure":{"kind":"vibes","unit":"次"},
"shape":{"kind":"linear"},"target_dose":1,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]}
''');
      expect(
        r.rejected.single.issues.map((QuantIssue q) => q.code),
        contains('R_UNKNOWN_MEASURE'),
      );
    });

    test('份额 0.7+0.7 归一后收下，并留一条 T_ 说明', () {
      final QuantDecodeResult r = run('''
{"items":[{"behavior_code":"c1","measure":{"kind":"duration_min","unit":"分钟"},
"shape":{"kind":"linear"},"target_dose":30,
"impact":[{"axis":"discipline","dim_kind":"ability","share":0.7},
          {"axis":"relation","axis_label":"关系","dim_kind":"experience","share":0.7}]}]}
''');
      expect(r.acceptedCount, 1, reason: r.rejected.toString());
      expect(
        r.accepted.single.issues.map((QuantIssue q) => q.code),
        contains('T_SHARE_RENORMALIZED'),
      );
    });

    test('只有 top-level 数组也能读', () {
      final QuantDecodeResult r = run('''
[{"behavior_code":"c1","measure":{"kind":"duration_min","unit":"分钟"},
"shape":{"kind":"linear"},"target_dose":30,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]
''');
      expect(r.acceptedCount, 1);
    });

    test('一片废话里没有 JSON → R_NO_JSON', () {
      final QuantDecodeResult r = run('我觉得都挺重要的，你看着办吧');
      expect(r.items, isEmpty);
      expect(r.batchIssues.single.code, 'R_NO_JSON');
    });

    test('括号不平衡 → R_NO_JSON（不抛异常）', () {
      final QuantDecodeResult r = run('{"items":[{"behavior_code":"c1"');
      expect(r.batchIssues.single.code, 'R_NO_JSON');
    });

    test('items 为空 → R_NO_ITEMS', () {
      final QuantDecodeResult r = run('{"items":[]}');
      expect(r.batchIssues.single.code, 'R_NO_ITEMS');
    });

    test('数组里混进字符串 → 跳过并记 R_BAD_ITEM，不影响其余', () {
      final QuantDecodeResult r = run('''
{"items":["随便说说",{"behavior_code":"c1","measure":{"kind":"count","unit":"次"},
"shape":{"kind":"linear"},"target_dose":3,
"impact":[{"axis":"discipline","dim_kind":"ability","share":1}]}]}
''');
      expect(r.items.length, 1);
      expect(r.batchIssues.single.code, 'R_BAD_ITEM');
      expect(r.acceptedCount, 1);
    });
  });

  group('extractJson 的括号配对', () {
    test('字符串里的花括号不参与计数', () {
      expect(
        extractJson('前 `{"a":"} not the end"}` 后'),
        '{"a":"} not the end"}',
      );
    });

    test('转义引号不打断字符串', () {
      expect(
        extractJson(r'x {"a":"say \"hi\" }"} y'),
        r'{"a":"say \"hi\" }"}',
      );
    });

    test('优先取更靠前的起点', () {
      expect(extractJson('[] {"a":1}'), '[]');
    });
  });
}
