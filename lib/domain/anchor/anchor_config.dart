/// 刻度标定层的系数表。
///
/// 为什么单独一个 config 对象，而不是塞进 `BalanceConfig`：
///
///   `BalanceConfig` 是结算流水线的系数表——改任何一个字段，从那天起重算，
///   曲线就会变。而刻度层产出的是**先验**，它不参与 `SettlementPipeline`。
///   把先验权重混进 `BalanceConfig` 的后果是：调一个"我觉得这事没那么重要"
///   的滑杆，历史 EXP 会跟着变——那是把主观判断写进事实账，恰好是这一层
///   要避免的事。
///
/// 所以这里的定位是：**同一条铁律（系数只住 config 对象，算法文件里不许有
/// 裸数字）的第二个配置对象**。它有自己的范围、自己的实验室分组，不参与
/// 主曲线重算。
///
/// 硬约束（改这个文件前先读）：
///   - `priorWeightCap` 不得超过 0.5。先验永远不许当证据用。
///   - `tierLargePrior` 只在实际出具证据后生效；未解锁时
///     `AnchorEngine` 会拒绝把它写进 [DeclaredImpact]。
///   - `aiProposalDiscount < 1.0`：AI 估的值天然比用户自己估的低一级。
library;

import 'anchor_models.dart';

/// 单条主观记录在图表上的误差带最小半宽（占总幅度比例）。
const double kSubjectiveBandFraction = 0.08;

class AnchorConfig {
  const AnchorConfig({
    // ---- 先验封顶 ----
    this.priorWeightCap = 0.5,
    this.tierSmallPrior = 0.15,
    this.tierMediumPrior = 0.30,
    this.tierMediumHighPrior = 0.45,
    this.tierLargePrior = 0.60,
    // ---- 来源折价 ----
    this.aiProposalDiscount = 0.60,
    this.aiTierCeiling = ImpactTier.mediumHigh,
    // ---- 各分类的 EXP 权重 ----
    this.formulaExpWeight = 1.0,
    this.subjectiveExpWeight = 0.0,
    this.semiObservableExpWeight = 0.05,
    // ---- 校验门 ----
    this.tierJumpMax = 1,
    this.sanitySuspectRatio = 3.0,
    this.sanityImplausibleRatio = 10.0,
    this.sanityConfidencePenalty = 0.20,
    this.noCitationDowngrade = 1,
    // ---- 引导流程 ----
    this.minBehaviors = 3,
    this.maxBehaviors = 5,
    // ---- 图表标记 ----
    this.priorBandHalfWidth = 6.0,
    this.priorBandFloorRatio = 0.5,
    this.subjectiveBandScale = 1.6,
    this.selfDeclaredOpacity = 0.55,
  });

  /// 先验权重的硬上限。规范写死 0.5，别调高。
  final double priorWeightCap;

  final double tierSmallPrior;
  final double tierMediumPrior;
  final double tierMediumHighPrior;

  /// 「大」的先验权重。只有在实测解锁后才可能被用到。
  final double tierLargePrior;

  /// AI 提议相对用户自估的折价。
  final double aiProposalDiscount;

  /// AI 能提议的最高档位。「大」必须来自实测。
  final ImpactTier aiTierCeiling;

  /// 可公式化行为的权重基准。
  final double formulaExpWeight;

  /// 仅主观可辨：不折成 EXP，也不参与扣分。
  final double subjectiveExpWeight;

  /// 半可观测：给一个极小权重表示"存在"，但不足以形成精确分。
  final double semiObservableExpWeight;

  /// 档位一次最多跳几档。防止"我今天心情好，全设成大"。
  final int tierJumpMax;

  /// 实测值超过参照区间上限多少倍算"可疑"（降置信度，不阻断）。
  final double sanitySuspectRatio;

  /// 超过多少倍算"不符合生理常识"（仍不阻断，只降置信度）。
  final double sanityImplausibleRatio;

  final double sanityConfidencePenalty;

  /// AI 提案缺引用时降几档。
  final int noCitationDowngrade;

  final int minBehaviors;
  final int maxBehaviors;

  final double priorBandHalfWidth;

  /// 误差带宽度随先验权重的插值下限：权重为 0 时带宽仍是 `floor × base`。
  final double priorBandFloorRatio;

  /// 主观类的误差带放大倍数——越不可观测，带越宽。
  final double subjectiveBandScale;

  final double selfDeclaredOpacity;

  double tierPrior(ImpactTier tier) {
    if (tier == ImpactTier.small) return tierSmallPrior;
    if (tier == ImpactTier.medium) return tierMediumPrior;
    if (tier == ImpactTier.mediumHigh) return tierMediumHighPrior;
    return tierLargePrior;
  }

  /// 夹到封顶。所有对外暴露权重的地方都必须过这一道。
  double clampPrior(double raw) =>
      raw < 0 ? 0 : (raw > priorWeightCap ? priorWeightCap : raw);

  AnchorConfig copyWith({
    double? priorWeightCap,
    double? tierSmallPrior,
    double? tierMediumPrior,
    double? tierMediumHighPrior,
    double? tierLargePrior,
    double? aiProposalDiscount,
    ImpactTier? aiTierCeiling,
    double? subjectiveExpWeight,
    double? semiObservableExpWeight,
    int? tierJumpMax,
    double? sanitySuspectRatio,
    double? sanityImplausibleRatio,
    double? sanityConfidencePenalty,
    int? noCitationDowngrade,
    int? minBehaviors,
    int? maxBehaviors,
    double? formulaExpWeight,
    double? priorBandHalfWidth,
    double? priorBandFloorRatio,
    double? subjectiveBandScale,
    double? selfDeclaredOpacity,
  }) =>
      AnchorConfig(
        priorWeightCap: priorWeightCap ?? this.priorWeightCap,
        tierSmallPrior: tierSmallPrior ?? this.tierSmallPrior,
        tierMediumPrior: tierMediumPrior ?? this.tierMediumPrior,
        tierMediumHighPrior: tierMediumHighPrior ?? this.tierMediumHighPrior,
        tierLargePrior: tierLargePrior ?? this.tierLargePrior,
        aiProposalDiscount: aiProposalDiscount ?? this.aiProposalDiscount,
        aiTierCeiling: aiTierCeiling ?? this.aiTierCeiling,
        formulaExpWeight: formulaExpWeight ?? this.formulaExpWeight,
        subjectiveExpWeight: subjectiveExpWeight ?? this.subjectiveExpWeight,
        semiObservableExpWeight:
            semiObservableExpWeight ?? this.semiObservableExpWeight,
        tierJumpMax: tierJumpMax ?? this.tierJumpMax,
        sanitySuspectRatio: sanitySuspectRatio ?? this.sanitySuspectRatio,
        sanityImplausibleRatio:
            sanityImplausibleRatio ?? this.sanityImplausibleRatio,
        sanityConfidencePenalty:
            sanityConfidencePenalty ?? this.sanityConfidencePenalty,
        noCitationDowngrade: noCitationDowngrade ?? this.noCitationDowngrade,
        minBehaviors: minBehaviors ?? this.minBehaviors,
        maxBehaviors: maxBehaviors ?? this.maxBehaviors,
        priorBandHalfWidth: priorBandHalfWidth ?? this.priorBandHalfWidth,
        priorBandFloorRatio: priorBandFloorRatio ?? this.priorBandFloorRatio,
        subjectiveBandScale: subjectiveBandScale ?? this.subjectiveBandScale,
        selfDeclaredOpacity: selfDeclaredOpacity ?? this.selfDeclaredOpacity,
      );

  /// 数值实验室用的扁平表。键名与字段名一致，改键即改契约。
  Map<String, double> toMap() => <String, double>{
        'priorWeightCap': priorWeightCap,
        'tierSmallPrior': tierSmallPrior,
        'tierMediumPrior': tierMediumPrior,
        'tierMediumHighPrior': tierMediumHighPrior,
        'tierLargePrior': tierLargePrior,
        'aiProposalDiscount': aiProposalDiscount,
        'aiTierCeiling': aiTierCeiling.index.toDouble(),
        'formulaExpWeight': formulaExpWeight,
        'subjectiveExpWeight': subjectiveExpWeight,
        'semiObservableExpWeight': semiObservableExpWeight,
        'tierJumpMax': tierJumpMax.toDouble(),
        'sanitySuspectRatio': sanitySuspectRatio,
        'sanityImplausibleRatio': sanityImplausibleRatio,
        'sanityConfidencePenalty': sanityConfidencePenalty,
        'noCitationDowngrade': noCitationDowngrade.toDouble(),
        'minBehaviors': minBehaviors.toDouble(),
        'maxBehaviors': maxBehaviors.toDouble(),
        'priorBandHalfWidth': priorBandHalfWidth,
        'priorBandFloorRatio': priorBandFloorRatio,
        'subjectiveBandScale': subjectiveBandScale,
        'selfDeclaredOpacity': selfDeclaredOpacity,
      };

  /// 从扁平表回填。缺项保持默认；未知键由调用方（ConfigRepository）拦。
  AnchorConfig withOverrides(Map<String, double> map) {
    double numOr(String key, double fallback) {
      final double? v = map[key];
      return v ?? fallback;
    }

    int intOr(String key, int fallback) {
      final double? v = map[key];
      if (v == null) return fallback;
      return v.round();
    }

    int tierIndex = intOr('aiTierCeiling', aiTierCeiling.index);
    if (tierIndex < 0) tierIndex = 0;
    if (tierIndex > ImpactTier.values.length - 1) {
      tierIndex = ImpactTier.values.length - 1;
    }

    return copyWith(
      priorWeightCap: numOr('priorWeightCap', priorWeightCap),
      tierSmallPrior: numOr('tierSmallPrior', tierSmallPrior),
      tierMediumPrior: numOr('tierMediumPrior', tierMediumPrior),
      tierMediumHighPrior: numOr('tierMediumHighPrior', tierMediumHighPrior),
      tierLargePrior: numOr('tierLargePrior', tierLargePrior),
      aiProposalDiscount: numOr('aiProposalDiscount', aiProposalDiscount),
      aiTierCeiling: ImpactTier.values[tierIndex],
      formulaExpWeight: numOr('formulaExpWeight', formulaExpWeight),
      subjectiveExpWeight:
          numOr('subjectiveExpWeight', subjectiveExpWeight),
      semiObservableExpWeight:
          numOr('semiObservableExpWeight', semiObservableExpWeight),
      tierJumpMax: intOr('tierJumpMax', tierJumpMax),
      sanitySuspectRatio: numOr('sanitySuspectRatio', sanitySuspectRatio),
      sanityImplausibleRatio:
          numOr('sanityImplausibleRatio', sanityImplausibleRatio),
      sanityConfidencePenalty:
          numOr('sanityConfidencePenalty', sanityConfidencePenalty),
      noCitationDowngrade: intOr('noCitationDowngrade', noCitationDowngrade),
      minBehaviors: intOr('minBehaviors', minBehaviors),
      maxBehaviors: intOr('maxBehaviors', maxBehaviors),
      priorBandHalfWidth: numOr('priorBandHalfWidth', priorBandHalfWidth),
      priorBandFloorRatio:
          numOr('priorBandFloorRatio', priorBandFloorRatio),
      subjectiveBandScale: numOr('subjectiveBandScale', subjectiveBandScale),
      selfDeclaredOpacity: numOr('selfDeclaredOpacity', selfDeclaredOpacity),
    );
  }
}

const AnchorConfig kDefaultAnchorConfig = AnchorConfig();
