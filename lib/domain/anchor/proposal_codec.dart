/// 与「网页版 AI」之间的离线交换协议（**不加网络权限**）。
///
/// 为什么不走 HTTP：
///   App 的承诺之一是「无 INTERNET 权限」（见 STATE 三之三）。接一个 API
///   就等于把"数据全程本地"这句话删掉。所以这里用**旁路**：
///
///     导出：把 [AnchorProposalCodec.buildRequestText] 生成的文本
///           （含我们的量化公式 + 严格输出格式）复制/分享给网页 AI；
///     导入：把 AI 的回复原文粘回来，[AnchorProposalCodec.decode] 逐条校验。
///
/// AI 的产出只有一种身份：**提案**（[ImpactSource.aiProposal]）。
///   - 权重按 `AnchorConfig.aiProposalDiscount` 再打折；
///   - 最高只能提议「中偏大」（「大」必须由实测解锁）；
///   - 没有引用依据 → 自动降一档；
///   - 用户逐条确认前不进任何展示数值，确认后转成普通先验（userPrior）。
///
/// 这样做的收益是「具体化」——AI 擅长把"维护关系"拆成"一次 20 分钟不被打断
/// 的深谈"；风险是「替你决定值多少」——后者被档位封顶 + 引用要求 +
/// 逐条确认三道闸挡住。
library;

import 'dart:convert';

import '../enums.dart';
import '../models/project_axis.dart';
import 'anchor_config.dart';
import 'anchor_engine.dart';
import 'anchor_models.dart';
import 'reference_ranges.dart';

/// 待标定的一项（导出时告诉 AI 有哪些活要干）。
class ProposalTarget {
  const ProposalTarget({
    required this.behaviorId,
    required this.label,
    required this.measurementClass,
    this.rangeIds = const <String>[],
    this.existingUnitLabel = '',
  });

  final String behaviorId;
  final String label;
  final MeasurementClass measurementClass;

  /// 允许 AI 引用的参照区间 id（空 = 只给 custom）。
  final List<String> rangeIds;

  final String existingUnitLabel;

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_id': behaviorId,
        'label': label,
        'measurement_class': measurementClass.name,
        'allowed_range_ids':
            rangeIds.isEmpty ? <String>['custom'] : rangeIds,
        if (existingUnitLabel.isNotEmpty) 'existing_unit': existingUnitLabel,
      };
}

/// 一条被接受的 AI 提案（尚未入库、尚未确认）。
class AiProposal {
  const AiProposal({
    required this.behaviorId,
    required this.unitLabel,
    required this.definitionText,
    required this.referenceObject,
    required this.referenceRangeId,
    required this.rawTier,
    required this.appliedTier,
    required this.rationale,
    required this.citation,
    this.notes = const <String>[],
  });

  final String behaviorId;
  final String unitLabel;
  final String definitionText;
  final String referenceObject;
  final String referenceRangeId;

  /// AI 原话里的档位（可能高于上限，仅留档对照）。
  final ImpactTier rawTier;

  /// 经过封顶 / 降档后实际会用的档位。
  final ImpactTier appliedTier;

  final String rationale;
  final String citation;

  /// 降档原因等，UI 逐条展示。
  final List<String> notes;

  bool get downgraded => appliedTier != rawTier;

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_id': behaviorId,
        'unit_label': unitLabel,
        'definition_text': definitionText,
        'reference_object': referenceObject,
        'reference_range_id': referenceRangeId,
        'raw_tier': rawTier.name,
        'applied_tier': appliedTier.name,
        'rationale': rationale,
        'citation': citation,
        'notes': notes,
      };

  static AiProposal fromJson(Map<String, Object?> json) => AiProposal(
        behaviorId: json['behavior_id']?.toString() ?? '',
        unitLabel: json['unit_label']?.toString() ?? '',
        definitionText: json['definition_text']?.toString() ?? '',
        referenceObject: json['reference_object']?.toString() ?? '',
        referenceRangeId: json['reference_range_id']?.toString() ?? 'custom',
        rawTier: ImpactTier.parse(json['raw_tier']?.toString() ?? ''),
        appliedTier: ImpactTier.parse(json['applied_tier']?.toString() ?? ''),
        rationale: json['rationale']?.toString() ?? '',
        citation: json['citation']?.toString() ?? '',
        notes: ((json['notes'] as List<Object?>?) ?? const <Object?>[])
            .map((Object? e) => e?.toString() ?? '')
            .toList(growable: false),
      );
}

/// 被拒的一条。`index` 是它在 AI 回复数组里的位置，方便用户回去找。
class ProposalRejection {
  const ProposalRejection({
    required this.index,
    required this.code,
    required this.message,
    this.behaviorId = '',
  });

  final int index;
  final String code;
  final String message;
  final String behaviorId;
}

class ProposalBundle {
  const ProposalBundle({
    required this.accepted,
    required this.rejected,
    required this.rawItemCount,
  });

  final List<AiProposal> accepted;
  final List<ProposalRejection> rejected;
  final int rawItemCount;

  bool get isEmpty => accepted.isEmpty && rejected.isEmpty;
  bool get hasAccepted => accepted.isNotEmpty;

  /// 导入页顶部那一行。
  String get summary {
    if (isEmpty) return '没有识别到任何条目——确认粘的是 AI 的完整回复';
    return '识别 ${rawItemCount} 条：${accepted.length} 条可用'
        '${rejected.isEmpty ? '' : '，${rejected.length} 条打回'}';
  }
}

class AnchorProposalCodec {
  const AnchorProposalCodec._();

  // ------------------------------------------------------------ 导出

  /// 生成给网页 AI 的完整请求文本。
  ///
  /// [expPerPoint] 从 `BalanceConfig.expPerPoint` 传进来——本层不 import
  /// core/config，避免 domain ↔ core 反向依赖。
  static String buildRequestText({
    required List<ProposalTarget> targets,
    required AnchorConfig config,
    required double expPerPoint,
    String extraContext = '',
  }) {
    final StringBuffer b = StringBuffer();
    b.writeln('你在帮我把"想追踪但说不清怎么量化"的行为，变成可执行的记录单位。'
        '只做两件事：把抽象项具体化成一个能事后判断真假的一次单位；'
        '在给定档位里挑一个，并说明依据。');
    b.writeln();
    b.writeln('## 硬约束（违反的条目会被自动打回，不要试）');
    b.writeln('1. 档位只能从这四个词里选：small / medium / mediumHigh。'
        '**不许给数字、不许给小数、不许自造中间档。**'
        'large 我这边锁着，只有实测才能解锁，你不要提。');
    b.writeln('2. 每条都必须有 rationale（为什么是这个档）和 citation'
        '（依据是什么：公共指引 / 你自己的换算 / 我说过的参照物）。'
        '没有 citation 会被自动降一档。');
    b.writeln('3. unit_label 是一句"怎么数一次"，必须含可验证的边界'
        '（时长、次数、字数、完成度）。禁止"适量""认真""高质量"这类无法核对的词。');
    b.writeln('4. 拿不准就往下调一档，并在 rationale 里说明拿不准在哪。'
        '不要为了显得懂而抬高。');
    b.writeln();
    b.writeln('## 我系统的量化规则（你挑的档位会按这张表变成先验权重）');
    b.writeln(_formulaBlock(config, expPerPoint));
    b.writeln();
    b.writeln('## 参照区间（只能引用下面这些 id）');
    b.writeln(_rangeBlock(targets));
    b.writeln();
    b.writeln('## 要处理的行为');
    b.writeln(const JsonEncoder.withIndent('  ')
        .convert(targets.map((ProposalTarget t) => t.toJson()).toList()));
    if (extraContext.trim().isNotEmpty) {
      b.writeln();
      b.writeln('## 我的补充上下文');
      b.writeln(extraContext.trim());
    }
    b.writeln();
    b.writeln('## 输出格式（只输出这个 JSON 数组，不要任何前后解释）');
    b.writeln('''[
  {
    "behavior_id": "上面列表里的 id，原样返回",
    "unit_label": "一次＝什么（简短名词短语）",
    "definition_text": "什么算一次、什么不算（一句话，可核对）",
    "reference_object": "跟你已知的某件事的对照（可选，没有就空字符串）",
    "reference_range_id": "引用的参照区间 id（必须是上面列出的）",
    "tier": "small | medium | mediumHigh",
    "rationale": "为什么是这个档，两句话以内",
    "citation": "依据来源"
  }
]''');
    return b.toString();
  }

  static String _formulaBlock(AnchorConfig config, double expPerPoint) {
    String pct(double v) => '${(v * 100).round()}%';

    final StringBuffer b = StringBuffer();
    b.writeln('- 档位 → 先验权重（我声明的影响，未实测前最多 '
        '${pct(config.priorWeightCap)}）：');
    b.writeln('  small ${pct(config.clampPrior(config.tierSmallPrior))} / '
        'medium ${pct(config.clampPrior(config.tierMediumPrior))} / '
        'mediumHigh ${pct(config.clampPrior(config.tierMediumHighPrior))} / '
        'large 锁定（实测后 ${pct(config.clampPrior(config.tierLargePrior))}）');
    b.writeln('- 你的提案权重还要再乘 ${config.aiProposalDiscount}：'
        '相当于比你直接说的低一档。这是故意的。');
    b.writeln('- 先验只用于展示与折价，不参与任何结算；一旦有实测证据，'
        '先验权重归零，改用实测反算的档位。');
    // 置信权重只从 Confidence 取，不在这里再写一遍 0.6/0.8/1.0。
    b.writeln('- 最终 EXP = 当日有效分 × 项目权重 × 状态乘数 × 置信权重'
        '（自报 ${Confidence.selfReport.weight} / '
        '推算 ${Confidence.formula.weight} / '
        '实测 ${Confidence.calibrated.weight}）× '
        '${expPerPoint.toStringAsFixed(2)} EXP/点。');
    b.writeln('- 「仅主观可辨」类（深度对话、情绪劳动、家务、育儿、等待、心流）'
        'EXP 权重恒为 ${config.subjectiveExpWeight}，并且永不参与扣分——'
        '你给这类挑的档位只影响趋势图的高低，不影响分数。');
    b.writeln('- 「半可观测」类（拖延、被动刷手机）只呈现时间占比，'
        '不作为惩罚依据。');
    return b.toString();
  }

  static String _rangeBlock(List<ProposalTarget> targets) {
    final Set<String> ids = <String>{'custom'};
    for (final ProposalTarget t in targets) {
      ids.addAll(t.rangeIds.isEmpty ? <String>['custom'] : t.rangeIds);
    }
    final StringBuffer b = StringBuffer();
    for (final String id in ids) {
      final ReferenceRange? r = referenceRangeById(id);
      if (r == null) continue;
      b.writeln('- `$id` ${r.title}（${r.measurementClass.label}）'
          '｜单位候选：${r.unitSuggestions.join(' / ')}'
          '｜区间：${r.bandSummary}'
          '｜出处：${r.sourceLabel}'
          '｜限定：${r.caveat}');
    }
    return b.toString();
  }

  // ------------------------------------------------------------ 导入

  /// 解析 AI 回复原文。容忍 ```json 围栏、前后废话、单个对象或数组。
  static ProposalBundle decode(
    String raw, {
    required List<ProposalTarget> targets,
    required AnchorConfig config,
  }) {
    final String? jsonText = extractJson(raw);
    if (jsonText == null) {
      return const ProposalBundle(
        accepted: <AiProposal>[],
        rejected: <ProposalRejection>[
          ProposalRejection(
            index: 0,
            code: 'R_NOT_JSON',
            message: '回复里没有可解析的 JSON。让 AI 只输出那个数组。',
          ),
        ],
        rawItemCount: 0,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      return ProposalBundle(
        accepted: const <AiProposal>[],
        rejected: <ProposalRejection>[
          ProposalRejection(
            index: 0,
            code: 'R_BAD_JSON',
            message: 'JSON 语法错误：${e.message}',
          ),
        ],
        rawItemCount: 0,
      );
    }

    final List<Object?> items;
    if (decoded is List<Object?>) {
      items = decoded;
    } else if (decoded is Map<Object?, Object?>) {
      final Object? inner = decoded['items'] ?? decoded['proposals'];
      items = inner is List<Object?> ? inner : <Object?>[decoded];
    } else {
      return const ProposalBundle(
        accepted: <AiProposal>[],
        rejected: <ProposalRejection>[
          ProposalRejection(
            index: 0,
            code: 'R_NOT_LIST',
            message: '最外层不是数组，也不是带 items 的对象。',
          ),
        ],
        rawItemCount: 0,
      );
    }

    final Map<String, ProposalTarget> byId = <String, ProposalTarget>{
      for (final ProposalTarget t in targets) t.behaviorId: t,
    };

    final List<AiProposal> accepted = <AiProposal>[];
    final List<ProposalRejection> rejected = <ProposalRejection>[];

    for (int i = 0; i < items.length; i++) {
      final Object? item = items[i];
      if (item is! Map<Object?, Object?>) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_NOT_OBJECT',
          message: '第 ${i + 1} 条不是对象。',
        ));
        continue;
      }
      final Map<String, Object?> m = item.cast<String, Object?>();
      final String behaviorId = m['behavior_id']?.toString().trim() ?? '';
      final ProposalTarget? target = byId[behaviorId];

      if (behaviorId.isEmpty || target == null) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_UNKNOWN_BEHAVIOR',
          message: 'behavior_id「$behaviorId」不在这次待标定列表里。',
          behaviorId: behaviorId,
        ));
        continue;
      }

      final String unit = m['unit_label']?.toString().trim() ?? '';
      if (unit.isEmpty) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_NO_UNIT',
          message: '「${target.label}」缺 unit_label：没法数就没法记。',
          behaviorId: behaviorId,
        ));
        continue;
      }

      final String definition = m['definition_text']?.toString().trim() ?? '';
      if (definition.isEmpty) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_NO_DEFINITION',
          message: '「${target.label}」缺 definition_text：'
              '事后无法判断"算不算一次"的单位不能拿去校准。',
          behaviorId: behaviorId,
        ));
        continue;
      }

      final String rationale = m['rationale']?.toString().trim() ?? '';
      if (rationale.isEmpty) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_NO_RATIONALE',
          message: '「${target.label}」缺 rationale：'
              '没有理由的档位没法审，也就没法用。',
          behaviorId: behaviorId,
        ));
        continue;
      }

      final String rawTierText = m['tier']?.toString().trim() ?? '';
      final ImpactTier? parsedTier = ImpactTier.tryParse(rawTierText);
      if (parsedTier == null) {
        rejected.add(ProposalRejection(
          index: i,
          code: 'R_FREE_NUMBER',
          message: '「${target.label}」的档位「$rawTierText」不在四档词表里。'
              '禁止自造数字档——请让它只输出 small / medium / mediumHigh。',
          behaviorId: behaviorId,
        ));
        continue;
      }

      // ---- 封顶 ----
      final List<String> notes = <String>[];
      ImpactTier applied = parsedTier;
      if (applied.rank > config.aiTierCeiling.rank) {
        applied = config.aiTierCeiling;
        notes.add('AI 想给「${parsedTier.label}」，已压到「${applied.label}」：'
            '「大」只能由实测解锁');
      }

      // ---- 缺引用降档 ----
      final String citation = m['citation']?.toString().trim() ?? '';
      if (citation.isEmpty && config.noCitationDowngrade > 0) {
        final ImpactTier before = applied;
        applied = _stepDown(applied, config.noCitationDowngrade);
        notes.add('没有依据（citation 为空），'
            '「${before.label}」自动降一档到「${applied.label}」');
      }

      // ---- 参照区间合法性 ----
      String rangeId = m['reference_range_id']?.toString().trim() ?? '';
      if (rangeId.isEmpty) rangeId = 'custom';
      final List<String> allowed = target.rangeIds.isEmpty
          ? <String>['custom']
          : target.rangeIds;
      if (!allowed.contains(rangeId) && rangeId != 'custom') {
        notes.add('引用了不在本次清单里的区间「$rangeId」，已改为 custom');
        rangeId = 'custom';
      }

      accepted.add(AiProposal(
        behaviorId: behaviorId,
        unitLabel: unit,
        definitionText: definition,
        referenceObject: m['reference_object']?.toString().trim() ?? '',
        referenceRangeId: rangeId,
        rawTier: parsedTier,
        appliedTier: applied,
        rationale: rationale,
        citation: citation,
        notes: notes,
      ));
    }

    return ProposalBundle(
      accepted: accepted,
      rejected: rejected,
      rawItemCount: items.length,
    );
  }

  static ImpactTier _stepDown(ImpactTier tier, int steps) {
    final int idx = tier.rank - steps;
    if (idx <= 0) return ImpactTier.small;
    if (idx >= ImpactTier.values.length) return ImpactTier.large;
    return ImpactTier.values[idx];
  }

  /// 从任意文本里抠出第一段 JSON（对象或数组），字符串内的括号不计。
  static String? extractJson(String raw) {
    final String text = raw.replaceAll('\uFEFF', '');
    int start = -1;
    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      if (ch == '{' || ch == '[') {
        start = i;
        break;
      }
    }
    if (start < 0) return null;

    final String open = text[start];
    final String close = open == '{' ? '}' : ']';
    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = start; i < text.length; i++) {
      final String ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == open) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  // ------------------------------------------------------------ 确认

  /// 用户逐条确认后调用：AI 提案 → 普通先验（userPrior）。
  ///
  /// 走的是和手动填写**完全相同**的一条路（[AnchorEngine.acceptAiProposal]），
  /// 因此不存在"AI 通道"这种旁路。
  static DeclaredImpact toDeclaredImpact({
    required AiProposal proposal,
    required AnchorEngine engine,
    required DateTime at,
  }) =>
      engine.acceptAiProposal(
        behaviorId: proposal.behaviorId,
        tier: proposal.appliedTier,
        at: at,
        note: 'AI 提议，已确认'
            '${proposal.citation.isEmpty ? '' : '（依据：${proposal.citation}）'}',
      );
}

// ---------------------------------------------------------------- 自建项目

/// 一个「内置库里没有、但我想追踪」的项目，AI 的具体化提案。
///
/// 和 [AiProposal] 的区别：那个只给单位与档位（行为已经存在），
/// 这个还要给**行为定义本身**（算哪个轴、正/负向、目标量多少）。
class NewBehaviorProposal {
  const NewBehaviorProposal({
    required this.name,
    required this.description,
    required this.category,
    required this.axis,
    required this.measurementClass,
    required this.unitLabel,
    required this.definitionText,
    required this.targetDose,
    required this.doseUnit,
    required this.referenceRangeId,
    required this.rawTier,
    required this.appliedTier,
    required this.rationale,
    required this.citation,
    this.referenceObject = '',
    this.notes = const <String>[],
  });

  final String name;
  final String description;
  final BehaviorCategory category;
  final ProjectAxis axis;
  final MeasurementClass measurementClass;
  final String unitLabel;
  final String definitionText;

  /// 一次的目标量（doseFraction 的分母）。必须 > 0。
  final double targetDose;
  final String doseUnit;

  final String referenceRangeId;
  final ImpactTier rawTier;
  final ImpactTier appliedTier;
  final String rationale;
  final String citation;
  final String referenceObject;
  final List<String> notes;

  bool get downgraded => appliedTier != rawTier;
}

/// 新项目的提案结果：要么给出提案，要么给一句能照做的原因。
typedef NewBehaviorResult = ({NewBehaviorProposal? proposal, String? error});

/// 自建项目的编解码入口（独立类，不是 extension——
/// extension 上的 static 成员调用起来别扭，而且这里用不到任何实例能力）。
class NewBehaviorCodec {
  const NewBehaviorCodec._();

  /// 给网页 AI 的「新项目」请求文本。
  ///
  /// 与 [AnchorProposalCodec.buildRequestText] 共用同一套公式与档位纪律，
  /// 多要三样东西：算哪个轴、正/负向、一次的目标量多少。
  static String buildNewBehaviorRequestText({
    required String name,
    required String description,
    required AnchorConfig config,
    required double expPerPoint,
    String axisHint = '',
  }) {
    final StringBuffer b = StringBuffer();
    b.writeln('我想在经验账本里加一个内置库没有的项目：**$name**。');
    if (description.trim().isNotEmpty) {
      b.writeln('我的描述：${description.trim()}');
    }
    b.writeln();
    b.writeln('帮我把它变成一个能每天打卡的条目。要给出四样东西：'
        '①它算哪个能力轴 ②正向还是负向 ③"一次"怎么数、一次算多少 ④影响量级。');
    b.writeln();
    b.writeln('## 硬约束（违反会被自动打回）');
    b.writeln('1. 档位只能 small / medium / mediumHigh 三选一，不给数字、不给小数。'
        'large 我这边锁着（只能实测解锁），你不要提。');
    b.writeln('2. 必须给 rationale（为什么这么定）与 citation（依据）。'
        '没有 citation 会自动降一档。');
    b.writeln('3. `definition_text` 必须能事后判断真假：含时长/次数/完成度之一。'
        '禁止"适量""认真"这类无法核对的词。');
    b.writeln('4. `target_dose` 是"一次算多少"的数值，必须 > 0，'
        '并且和 `dose_unit` 配得上（例：target_dose=45, dose_unit="分钟"）。'
        '不要给"视情况而定"。');
    b.writeln('5. `axis` 只能取：strength（体能）/ cardio（心肺）/ memory（词汇）/ '
        'writing（写作）/ discipline（自律）。拿不准就选最接近的那个，并在 rationale 说明。');
    b.writeln('6. `category` 只能取：positive（做了加分）/ negative（做了扣分）/ '
        'offPlan（计划外）。');
    b.writeln();
    b.writeln('## 我系统的量化规则（你定的档位与目标量会按这张规则走）');
    b.writeln(_publicFormulaBlock(config, expPerPoint));
    b.writeln();
    if (axisHint.trim().isNotEmpty) {
      b.writeln('## 我倾向的轴');
      b.writeln(axisHint.trim());
      b.writeln();
    }
    b.writeln('## 参照区间（可以引用，用来定档位）');
    b.writeln(_publicRangeBlock());
    b.writeln();
    b.writeln('## 输出格式（只输出这个 JSON 对象，不要任何解释）');
    b.writeln('''{
  "name": "项目名（沿用我给的，或更准的短名）",
  "description": "一句话说明它是什么",
  "category": "positive | negative | offPlan",
  "axis": "strength | cardio | memory | writing | discipline",
  "measurement_class": "formula | subjective | semiObservable",
  "unit_label": "一次＝什么（简短名词短语）",
  "definition_text": "什么算一次、什么不算（可核对）",
  "target_dose": 45,
  "dose_unit": "分钟",
  "reference_object": "跟我已知的某件事对照（可选，没有就空串）",
  "reference_range_id": "custom 或上面列出的 id",
  "tier": "small | medium | mediumHigh",
  "rationale": "为什么这么定，两句话以内",
  "citation": "依据来源"
}''');
    return b.toString();
  }

  static String _publicFormulaBlock(AnchorConfig config, double expPerPoint) {
    String pct(double v) => '${(v * 100).round()}%';
    final StringBuffer b = StringBuffer();
    b.writeln('- 档位 → 先验权重（未实测前最多 ${pct(config.priorWeightCap)}）：'
        'small ${pct(config.clampPrior(config.tierSmallPrior))} / '
        'medium ${pct(config.clampPrior(config.tierMediumPrior))} / '
        'mediumHigh ${pct(config.clampPrior(config.tierMediumHighPrior))}');
    b.writeln('- 每次记录的计入比例 = 实际量 ÷ target_dose（超过 1.5 按 1.5 封顶），'
        '再折算成当日有效分。');
    b.writeln('- 最终 EXP = 当日有效分 × 该轴权重 × 状态乘数 × 置信权重'
        '（自报 ${Confidence.selfReport.weight} / 推算 ${Confidence.formula.weight} / '
        '实测 ${Confidence.calibrated.weight}）× '
        '${expPerPoint.toStringAsFixed(2)} EXP/点。');
    b.writeln('- 「subjective」类不折 EXP、不参与扣分；「semiObservable」只呈现时间占比。'
        '拿不准就选 subjective，宁可不加分，也不要造分数。');
    return b.toString();
  }

  static String _publicRangeBlock() {
    final StringBuffer b = StringBuffer();
    for (final ReferenceRange r in kReferenceRanges) {
      b.writeln('- `$r.id` ${r.title}（${r.measurementClass.label}）'
          '｜${r.bandSummary}｜出处：${r.sourceLabel}');
    }
    return b.toString();
  }

  /// 解析 AI 给的新项目提案。**逐条校验，坏的就给原因。**
  static NewBehaviorResult decodeNewBehavior(
    String raw, {
    required AnchorConfig config,
  }) {
    final String? jsonText = AnchorProposalCodec.extractJson(raw);
    if (jsonText == null) {
      return (proposal: null, error: '回复里没有可解析的 JSON。让 AI 只输出那个对象。');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      return (proposal: null, error: 'JSON 语法错误：${e.message}');
    }
    if (decoded is! Map<Object?, Object?>) {
      return (proposal: null, error: '最外层不是对象。');
    }
    final Map<String, Object?> m = decoded.cast<String, Object?>();

    final String name = m['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      return (proposal: null, error: '缺 name：没有项目名没法建条目。');
    }
    final String unit = m['unit_label']?.toString().trim() ?? '';
    if (unit.isEmpty) {
      return (proposal: null, error: '缺 unit_label：没有单位就没法算"几次"。');
    }
    final String definition = m['definition_text']?.toString().trim() ?? '';
    if (definition.isEmpty) {
      return (proposal: null, error: '缺 definition_text：事后判断不了"算不算一次"的条目不能用。');
    }
    final String rationale = m['rationale']?.toString().trim() ?? '';
    if (rationale.isEmpty) {
      return (proposal: null, error: '缺 rationale：没有理由的定档没法审。');
    }
    final double? target = (m['target_dose'] as num?)?.toDouble();
    if (target == null || target <= 0) {
      return (proposal: null, error: 'target_dose 必须是大于 0 的数字（一次算多少）。');
    }

    final ImpactTier? parsedTier = ImpactTier.tryParse(m['tier']?.toString() ?? '');
    if (parsedTier == null) {
      return (
        proposal: null,
        error: 'tier「${m['tier']}」不在三档词表里。禁止自造数字档。',
      );
    }

    final List<String> notes = <String>[];
    ImpactTier applied = parsedTier;
    if (applied.rank > config.aiTierCeiling.rank) {
      applied = config.aiTierCeiling;
      notes.add('AI 想给「${parsedTier.label}」，已压到「${applied.label}」：'
          '「大」只能由实测解锁');
    }
    final String citation = m['citation']?.toString().trim() ?? '';
    if (citation.isEmpty && config.noCitationDowngrade > 0) {
      final ImpactTier before = applied;
      final int idx = applied.rank - config.noCitationDowngrade;
      applied = idx <= 0 ? ImpactTier.small : ImpactTier.values[idx];
      notes.add('没有依据（citation 为空），「${before.label}」降到「${applied.label}」');
    }

    final String rangeId = m['reference_range_id']?.toString().trim() ?? 'custom';

    return (
      proposal: NewBehaviorProposal(
        name: name,
        description: m['description']?.toString().trim() ?? '',
        category: _categoryOf(m['category']?.toString() ?? ''),
        axis: ProjectAxis.parse(m['axis']?.toString() ?? 'discipline'),
        measurementClass:
            MeasurementClass.parse(m['measurement_class']?.toString() ?? ''),
        unitLabel: unit,
        definitionText: definition,
        targetDose: target,
        doseUnit: m['dose_unit']?.toString().trim() ?? '次',
        referenceRangeId: referenceRangeById(rangeId) == null ? 'custom' : rangeId,
        rawTier: parsedTier,
        appliedTier: applied,
        rationale: rationale,
        citation: citation,
        referenceObject: m['reference_object']?.toString().trim() ?? '',
        notes: notes,
      ),
      error: null,
    );
  }

  static BehaviorCategory _categoryOf(String raw) {
    for (final BehaviorCategory c in BehaviorCategory.values) {
      if (c.name == raw) return c;
    }
    if (raw == 'negative' || raw == '负向') return BehaviorCategory.negative;
    if (raw == 'offPlan' || raw == '计划外') return BehaviorCategory.offPlan;
    return BehaviorCategory.positive;
  }
}
