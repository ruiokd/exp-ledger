/// 刻度标定层（Anchor Layer）的数据模型。
///
/// 这一层解决的是「有行为、但量化公式缺个人参数」的那一类：
/// 由用户定义**怎么量**（[UserAnchor]），由系统决定**值多少**（[ImpactTier]
/// → 权重），由现实**校正到底多少**（[AnchorEvidence] → 覆盖 [DeclaredImpact]）。
///
/// 边界（不可越）：
///   - 本文件与同目录其余文件只依赖 `dart:core` / `dart:convert` 与
///     `lib/domain/enums.dart`，不碰 Flutter、不碰 sqflite。
///   - 本层产出的是**先验**，永远不直接写 `daily_log`，也不进
///     `SettlementPipeline`。它只影响置信折价与图表上的自声明标记。
library;

import '../enums.dart';

/// 行为的可量化程度。它决定**走哪条路**，不决定「值多少」。
enum MeasurementClass {
  /// 有公式缺个人参数：采集单位定义 + 基线测试 → 公式计算 + 实测校准。
  formula,

  /// 无公式、仅主观可辨：深度对话、情绪劳动、专注质量、家务、育儿、
  /// 通勤、等待、心流。只记录单位与档位，输出趋势与定性描述，
  /// EXP 权重为 0，且永不参与扣分。
  subjective,

  /// 半可观测：拖延、被动刷手机。以时间占比呈现，不给精确分。
  semiObservable;

  String get label {
    if (this == MeasurementClass.formula) return '可公式化';
    if (this == MeasurementClass.subjective) return '仅主观可辨';
    return '半可观测';
  }

  String get hint {
    if (this == MeasurementClass.formula) {
      return '有公式、缺你个人的参数：先定义单位，再用一次基线测试把参数测出来';
    }
    if (this == MeasurementClass.subjective) {
      return '没有可查证的公式：只记单位和档位，看趋势，不折成 EXP';
    }
    return '能看到时间占比，但边界模糊：按占比记录，不给精确分';
  }

  /// 是否允许折成 EXP。主观类恒为 false。
  bool get mayProduceExp => this == MeasurementClass.formula;

  /// 是否允许产生负向扣分。只有可公式化的行为才允许。
  bool get mayDeduct => this == MeasurementClass.formula;

  static MeasurementClass parse(String raw) {
    for (final MeasurementClass c in MeasurementClass.values) {
      if (c.name == raw) return c;
    }
    return MeasurementClass.subjective;
  }
}

/// 量级档位。四档固定，禁止自由填写任意数字。
///
/// 「大」只能由实测证据解锁——见 `AnchorEngine.checkTierChange`。
enum ImpactTier {
  small,
  medium,
  mediumHigh,
  large;

  /// 档位序。用于单调性校验与「跳档不得超过一档」。
  int get rank => index;

  String get label {
    if (this == ImpactTier.small) return '小';
    if (this == ImpactTier.medium) return '中';
    if (this == ImpactTier.mediumHigh) return '中偏大';
    return '大';
  }

  /// 回执与设置页用的一句话解释（为什么这一档值这么多）。
  String get meaning {
    if (this == ImpactTier.small) return '做不做都行，影响当天可见度很低';
    if (this == ImpactTier.medium) return '漏掉会察觉得到，但一天内能补回来';
    if (this == ImpactTier.mediumHigh) return '会挤掉别的事，或影响接下来一两天的状态';
    return '会改变接下来几天的主要安排，且难以临时补回';
  }

  static ImpactTier? tryParse(String raw) {
    final String key = raw.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');
    if (key.isEmpty) return null;
    if (key == 'small' || key == 's' || key == '小') return ImpactTier.small;
    if (key == 'medium' || key == 'mid' || key == 'm' || key == '中') {
      return ImpactTier.medium;
    }
    if (key == 'mediumhigh' || key == 'midhigh' || key == 'mh' || key == '中偏大') {
      return ImpactTier.mediumHigh;
    }
    if (key == 'large' || key == 'l' || key == '大') return ImpactTier.large;
    return null;
  }

  static ImpactTier parse(String raw) => tryParse(raw) ?? ImpactTier.medium;
}

/// 影响声明的来源。**只有 [userPrior] 被视为可信输入**。
enum ImpactSource {
  /// 用户自己声明的档位。可信、长期复用，但仍是先验。
  userPrior,

  /// AI（含网页版）按我们的公式框架给出的估算。天然低一级：必须经用户
  /// 逐条确认才能转为 [userPrior]，确认前不进任何展示数值。
  aiProposal,

  /// 实测反算出来的档位。唯一能覆盖先验的东西。
  evidence;

  bool get isTrustedInput => this == ImpactSource.userPrior;
  bool get isEvidence => this == ImpactSource.evidence;

  String get code => name;

  String get label {
    if (this == ImpactSource.userPrior) return '你估的';
    if (this == ImpactSource.aiProposal) return 'AI 提议（未确认）';
    return '实测反算';
  }

  static ImpactSource parse(String raw) {
    for (final ImpactSource s in ImpactSource.values) {
      if (s.name == raw) return s;
    }
    return ImpactSource.userPrior;
  }
}

/// 实测证据的种类。决定「这次反算有多硬」。
enum EvidenceKind {
  /// 标准化校准测试（如 5RM、最大摄氧量递增测试、复习保持率测试）。
  measuredTest,

  /// 趋势反推（如体重 28 天斜率、睡眠时长与次日状态的相关）。
  bodyTrend,

  /// 保持率测试（回忆正确率、动作质量复测）。
  retentionTest,

  /// 连续时间占比（半可观测行为的唯一合法证据）。
  timeShare;

  String get label {
    if (this == EvidenceKind.measuredTest) return '校准测试';
    if (this == EvidenceKind.bodyTrend) return '趋势反推';
    if (this == EvidenceKind.retentionTest) return '保持率测试';
    return '时间占比';
  }

  /// 能反算出档位的，才算「校准级」证据。
  bool get canDeriveTier => this != EvidenceKind.timeShare;

  static EvidenceKind parse(String raw) {
    for (final EvidenceKind k in EvidenceKind.values) {
      if (k.name == raw) return k;
    }
    return EvidenceKind.timeShare;
  }
}

/// 一条刻度变更记录。**不追溯**：只影响变更点之后的记录。
class AnchorRevision {
  const AnchorRevision({
    required this.at,
    required this.field,
    required this.from,
    required this.to,
    required this.reason,
  });

  /// 变更发生的时刻。图表上的刻度变更点就是这条的 [at]。
  final DateTime at;
  final String field;
  final String from;
  final String to;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        'field': field,
        'from': from,
        'to': to,
        'reason': reason,
      };

  static AnchorRevision fromJson(Map<String, Object?> json) => AnchorRevision(
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime(1970),
        field: json['field']?.toString() ?? '',
        from: json['from']?.toString() ?? '',
        to: json['to']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

/// 用户定义的单位。可信输入，长期复用。
///
/// 关键点：**单位是用户定的，不是系统猜的**。系统只负责给出参照区间
/// （见 `reference_ranges.dart`），用户在区间上「调整」，而不是从零发明。
class UserAnchor {
  const UserAnchor({
    required this.behaviorId,
    required this.unitLabel,
    required this.definitionText,
    required this.referenceObject,
    required this.measurementClass,
    required this.referenceRangeId,
    required this.calibratedAt,
    this.revisionHistory = const <AnchorRevision>[],
  });

  final String behaviorId;

  /// 「一次」叫什么。如「一次有效组」「一次 20 分钟深谈」「一页」。
  final String unitLabel;

  /// 什么算「一次」。必须能在事后判断真假，否则这条记录没有校准价值。
  final String definitionText;

  /// 参照物。让抽象单位有可比锚点，如「相当于我平时跑步 20 分钟的疲劳度」。
  final String referenceObject;

  final MeasurementClass measurementClass;

  /// 系统参照区间 id（`reference_ranges.dart` 的 [ReferenceRange.id]）。
  final String referenceRangeId;

  final DateTime calibratedAt;

  /// 刻度变更历史。改动单位不重算历史，只在图表上标变更点。
  final List<AnchorRevision> revisionHistory;

  /// 图表要画的刻度变更点。
  List<DateTime> get changePoints =>
      revisionHistory.map((AnchorRevision r) => r.at).toList(growable: false);

  bool get isUsable => unitLabel.trim().isNotEmpty;

  /// 改刻度：返回新实例，并追加一条 revision。**旧记录不重算。**
  UserAnchor revise({
    required DateTime at,
    String? unitLabel,
    String? definitionText,
    String? referenceObject,
    String? referenceRangeId,
    String reason = '',
  }) {
    final List<AnchorRevision> history = <AnchorRevision>[
      ...revisionHistory,
    ];
    final String nextUnit = unitLabel ?? this.unitLabel;
    final String nextDef = definitionText ?? this.definitionText;
    final String nextObject = referenceObject ?? this.referenceObject;
    final String nextRange = referenceRangeId ?? this.referenceRangeId;

    if (nextUnit != this.unitLabel) {
      history.add(AnchorRevision(
        at: at,
        field: 'unitLabel',
        from: this.unitLabel,
        to: nextUnit,
        reason: reason,
      ));
    }
    if (nextDef != this.definitionText) {
      history.add(AnchorRevision(
        at: at,
        field: 'definitionText',
        from: this.definitionText,
        to: nextDef,
        reason: reason,
      ));
    }
    if (nextObject != this.referenceObject) {
      history.add(AnchorRevision(
        at: at,
        field: 'referenceObject',
        from: this.referenceObject,
        to: nextObject,
        reason: reason,
      ));
    }
    if (nextRange != this.referenceRangeId) {
      history.add(AnchorRevision(
        at: at,
        field: 'referenceRangeId',
        from: this.referenceRangeId,
        to: nextRange,
        reason: reason,
      ));
    }

    return UserAnchor(
      behaviorId: behaviorId,
      unitLabel: nextUnit,
      definitionText: nextDef,
      referenceObject: nextObject,
      measurementClass: measurementClass,
      referenceRangeId: nextRange,
      calibratedAt: calibratedAt,
      revisionHistory: history,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_id': behaviorId,
        'unit_label': unitLabel,
        'definition_text': definitionText,
        'reference_object': referenceObject,
        'measurement_class': measurementClass.name,
        'reference_range_id': referenceRangeId,
        'calibrated_at': calibratedAt.toIso8601String(),
        'revision_history': revisionHistory
            .map((AnchorRevision r) => r.toJson())
            .toList(growable: false),
      };

  static UserAnchor fromJson(Map<String, Object?> json) {
    final List<Object?> raw = (json['revision_history'] as List<Object?>?) ??
        const <Object?>[];
    return UserAnchor(
      behaviorId: json['behavior_id']?.toString() ?? '',
      unitLabel: json['unit_label']?.toString() ?? '',
      definitionText: json['definition_text']?.toString() ?? '',
      referenceObject: json['reference_object']?.toString() ?? '',
      measurementClass:
          MeasurementClass.parse(json['measurement_class']?.toString() ?? ''),
      referenceRangeId: json['reference_range_id']?.toString() ?? '',
      calibratedAt:
          DateTime.tryParse(json['calibrated_at']?.toString() ?? '') ??
              DateTime(1970),
      revisionHistory: raw
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) =>
              AnchorRevision.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
    );
  }
}

/// 用户声明的影响。**只是先验**：`weight ≤ cap`（默认 0.5），
/// 一旦出现校准级证据，[replacedBy] 指向该证据，权重归零。
class DeclaredImpact {
  const DeclaredImpact({
    required this.behaviorId,
    required this.tier,
    required this.source,
    required this.weight,
    required this.declaredAt,
    this.replacedBy,
    this.note = '',
  });

  final String behaviorId;
  final ImpactTier tier;
  final ImpactSource source;

  /// 已按 `AnchorConfig.priorWeightCap` 夹过的先验权重。
  final double weight;

  final DateTime declaredAt;

  /// 覆盖它的证据 id（`AnchorEvidence.id`）。null = 先验仍生效。
  final String? replacedBy;

  final String note;

  bool get isOverridden => replacedBy != null && replacedBy!.isNotEmpty;

  DeclaredImpact copyWith({
    ImpactTier? tier,
    ImpactSource? source,
    double? weight,
    String? replacedBy,
    String? note,
    bool clearReplacedBy = false,
  }) =>
      DeclaredImpact(
        behaviorId: behaviorId,
        tier: tier ?? this.tier,
        source: source ?? this.source,
        weight: weight ?? this.weight,
        declaredAt: declaredAt,
        replacedBy: clearReplacedBy ? null : (replacedBy ?? this.replacedBy),
        note: note ?? this.note,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_id': behaviorId,
        'tier': tier.name,
        'source': source.name,
        'weight': weight,
        'declared_at': declaredAt.toIso8601String(),
        'replaced_by': replacedBy,
        'note': note,
      };

  static DeclaredImpact fromJson(Map<String, Object?> json) => DeclaredImpact(
        behaviorId: json['behavior_id']?.toString() ?? '',
        tier: ImpactTier.parse(json['tier']?.toString() ?? ''),
        source: ImpactSource.parse(json['source']?.toString() ?? ''),
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
        declaredAt: DateTime.tryParse(json['declared_at']?.toString() ?? '') ??
            DateTime(1970),
        replacedBy: json['replaced_by']?.toString(),
        note: json['note']?.toString() ?? '',
      );
}

/// 实测证据。唯一能覆盖先验的东西。
class AnchorEvidence {
  const AnchorEvidence({
    required this.id,
    required this.behaviorId,
    required this.kind,
    required this.measuredValue,
    required this.unit,
    required this.derivedTier,
    required this.performedAt,
    this.note = '',
    this.confidence = Confidence.calibrated,
  });

  final String id;
  final String behaviorId;
  final EvidenceKind kind;
  final double measuredValue;
  final String unit;

  /// 由实测值反算出的档位。写死在这里，方便 UI 直接对比先验。
  final ImpactTier derivedTier;

  final DateTime performedAt;
  final String note;

  /// 永远是 calibrated 起步；生理合理性复核不过时会被降到 formula。
  final Confidence confidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'behavior_id': behaviorId,
        'kind': kind.name,
        'measured_value': measuredValue,
        'unit': unit,
        'derived_tier': derivedTier.name,
        'performed_at': performedAt.toIso8601String(),
        'note': note,
        'confidence': confidence.name,
      };

  static AnchorEvidence fromJson(Map<String, Object?> json) => AnchorEvidence(
        id: json['id']?.toString() ?? '',
        behaviorId: json['behavior_id']?.toString() ?? '',
        kind: EvidenceKind.parse(json['kind']?.toString() ?? ''),
        measuredValue: (json['measured_value'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        derivedTier: ImpactTier.parse(json['derived_tier']?.toString() ?? ''),
        performedAt:
            DateTime.tryParse(json['performed_at']?.toString() ?? '') ??
                DateTime(1970),
        note: json['note']?.toString() ?? '',
        confidence: Confidence.parse(json['confidence']?.toString() ?? ''),
      );
}

/// 自声明数据在 UI 上的独立视觉标记：空心点 + 虚线误差带。
///
/// 只要一条数据的来源是 `userPrior`（含未经实测确认的 AI 提议），
/// 就必须带这个标记，和公式/实测数据区分开。
class SelfDeclaredMarker {
  const SelfDeclaredMarker({
    required this.hollow,
    required this.dashed,
    required this.bandHalfWidth,
  });

  final bool hollow;
  final bool dashed;

  /// 误差带半宽（单位与图表 y 轴一致）。档位越不确定越宽。
  final double bandHalfWidth;

  static const SelfDeclaredMarker formula = SelfDeclaredMarker(
    hollow: false,
    dashed: false,
    bandHalfWidth: 0,
  );
}

/// 个人刻度卡片（Step 4 产物）。一个行为一张。
class AnchorCard {
  const AnchorCard({
    required this.behaviorId,
    required this.anchor,
    required this.impact,
    this.evidence,
  });

  final String behaviorId;
  final UserAnchor anchor;
  final DeclaredImpact impact;

  /// 最近一次实测证据。有它就意味着先验已经被覆盖。
  final AnchorEvidence? evidence;

  MeasurementClass get measurementClass => anchor.measurementClass;

  bool get isCalibrated => evidence != null && impact.isOverridden;

  /// 卡片上的两行摘要。
  String get unitSummary => '一次 = ${anchor.unitLabel}'
      '${anchor.referenceObject.isEmpty ? '' : '（参照：${anchor.referenceObject}）'}';

  String get tierSummary =>
      '${impact.tier.label}${impact.isOverridden ? '（已被实测覆盖）' : '（先验，待实测修正）'}';
}
