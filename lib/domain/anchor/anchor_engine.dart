/// 刻度标定层的全部判定逻辑。**纯函数，无时钟、无随机、无 IO。**
///
/// 一条数据从"用户说这事值中偏大"走到"实测说是中"，只经过这里：
///
///   UserAnchor（怎么量）
///     → DeclaredImpact（先验多重，≤0.5）
///     → AnchorEvidence（实测多重，calibrated）
///     → WeightResolution（谁生效、差多少、UI 该说什么）
///
/// 所有对外返回的权重都已经过 [AnchorConfig.priorWeightCap] 夹取，
/// 调用方不需要（也不许）自己再夹一次。
library;

import '../enums.dart';
import 'anchor_config.dart';
import 'anchor_models.dart';
import 'reference_ranges.dart';

/// 权重裁决结果。UI 只读这个，不自己算。
class WeightResolution {
  const WeightResolution({
    required this.effectiveWeight,
    required this.appliedSource,
    required this.declaredWeight,
    required this.priorStillActive,
    required this.uiNote,
    required this.marker,
    this.declaredTier,
    this.measuredTier,
    this.evidenceId,
  });

  /// 最终拿去乘的权重。实测存在时 = 实测权重；否则 = 先验权重（≤0.5）。
  final double effectiveWeight;

  final ImpactSource appliedSource;

  /// 用户当初声明的权重（保留下来做对照，永远不参与结算）。
  final double declaredWeight;

  final bool priorStillActive;

  /// 一句话说明。设置页与明细页共用同一句，避免两处措辞漂移。
  final String uiNote;

  /// 图表标记：自声明数据必须空心 + 虚线。
  final SelfDeclaredMarker marker;

  final ImpactTier? declaredTier;
  final ImpactTier? measuredTier;
  final String? evidenceId;

  bool get isCalibrated => !priorStillActive && evidenceId != null;
}

/// 档位调整的许可结论。
class TierChangeVerdict {
  const TierChangeVerdict({
    required this.ok,
    required this.code,
    required this.message,
    this.appliedTier,
    this.downgraded = false,
  });

  final bool ok;

  /// 机器可读的原因码，测试与埋点（本地）都按它断言。
  final String code;

  final String message;

  /// 实际会写入的档位。被拒时为 null。
  final ImpactTier? appliedTier;

  /// 是否被降档放行（不是拒绝，但改了值）。
  final bool downgraded;
}

/// 生理合理性复核。**只降置信度，不阻断记录。**
enum SanityLevel { ok, suspect, implausible }

class SanityVerdict {
  const SanityVerdict({
    required this.level,
    required this.confidencePenalty,
    required this.note,
  });

  final SanityLevel level;
  final double confidencePenalty;
  final String note;

  bool get blocks => false;
}

/// 刻度变更的作用范围：**不追溯**。
class RecomputeScope {
  const RecomputeScope({
    required this.usesNewScale,
    required this.mustMarkPoint,
    required this.note,
  });

  /// 这一天（或之后）才用新刻度。
  final bool usesNewScale;

  /// 图表上要在变更点画竖线。
  final bool mustMarkPoint;

  final String note;
}

class AnchorEngine {
  const AnchorEngine([this.config = kDefaultAnchorConfig]);

  final AnchorConfig config;

  // ------------------------------------------------------------ 分类 → 路径

  /// 这类行为能产出多少 EXP 权重。主观类恒 0，半可观测极小。
  double expWeightFor(MeasurementClass cls) {
    if (cls == MeasurementClass.formula) return config.formulaExpWeight;
    if (cls == MeasurementClass.semiObservable) {
      return config.semiObservableExpWeight;
    }
    return config.subjectiveExpWeight;
  }

  /// 这类行为能不能扣分。只有可公式化的才行。
  bool mayDeduct(MeasurementClass cls) => cls.mayDeduct;

  /// 半可观测行为只输出时间占比，不输出精确分。
  bool prefersTimeShare(MeasurementClass cls) =>
      cls == MeasurementClass.semiObservable;

  // ------------------------------------------------------------ 先验

  /// 档位 + 来源 → 先验权重。**已夹到 [AnchorConfig.priorWeightCap]。**
  double priorWeightFor({
    required ImpactTier tier,
    required ImpactSource source,
  }) {
    double raw = config.tierPrior(tier);
    if (source == ImpactSource.aiProposal) {
      raw = raw * config.aiProposalDiscount;
    }
    return config.clampPrior(raw);
  }

  /// 建立一条先验声明。
  ///
  /// [hasCalibratedEvidence] 为 true 时不允许写入新先验（先验已被证据取代，
  /// 再写入会造成"两套数并存"）；此时返回的证据覆盖版需要调用方先删证据。
  DeclaredImpact declare({
    required String behaviorId,
    required ImpactTier tier,
    required ImpactSource source,
    required DateTime at,
    bool hasCalibratedEvidence = false,
    String note = '',
    String? replaceEvidenceId,
  }) {
    final double weight = priorWeightFor(tier: tier, source: source);
    return DeclaredImpact(
      behaviorId: behaviorId,
      tier: tier,
      source: source,
      weight: weight,
      declaredAt: at,
      note: note,
      replacedBy: replaceEvidenceId,
    );
  }

  /// 用户逐条确认一条 AI 提议 → 转为 userPrior。
  ///
  /// 注意：确认后身份是 userPrior（它现在是你的判断），但 [DeclaredImpact.note]
  /// 里会留一句来源，方便以后回看"这条当初是 AI 提的"。
  DeclaredImpact acceptAiProposal({
    required String behaviorId,
    required ImpactTier tier,
    required DateTime at,
    String note = 'AI 提议，已确认',
  }) =>
      declare(
        behaviorId: behaviorId,
        tier: tier,
        source: ImpactSource.userPrior,
        at: at,
        note: note,
      );

  // ------------------------------------------------------------ 覆盖

  /// 先验 vs 证据：谁生效、差多少、UI 说什么。
  ///
  /// 规则：
  ///   - 没有证据 → 先验生效（≤0.5），标空心 + 虚线。
  ///   - 有证据 → 先验权重归零（`evidenceOverrideFloor`），生效的是证据档位，
  ///     来源 = evidence，标记变成实线（因为它是实测）。
  ///   - 证据存在但 [DeclaredImpact.replacedBy] 还没指过去 → 视为"尚未落账"，
  ///     仍然按先验走，并在 [WeightResolution.uiNote] 里提示需要一次写入。
  WeightResolution resolve({
    required DeclaredImpact impact,
    AnchorEvidence? evidence,
    MeasurementClass measurementClass = MeasurementClass.formula,
  }) {
    // 注意：这里必须直接判 `evidence != null`，不能先算成 bool 变量再判——
    // Dart 的类型提升不穿过布尔变量，写成 `final bool linked = evidence != null;`
    // 之后 `if (linked) evidence.id` 是编译错误（只报类型，不报语法）。
    if (evidence != null &&
        impact.isOverridden &&
        impact.replacedBy == evidence.id) {
      final double w = config.clampPrior(config.tierPrior(evidence.derivedTier));
      return WeightResolution(
        effectiveWeight: w,
        appliedSource: ImpactSource.evidence,
        declaredWeight: impact.weight,
        priorStillActive: false,
        uiNote: '${divergenceSentence(
          declared: impact.tier,
          measured: evidence.derivedTier,
        )}（证据：${evidence.kind.label}，${evidence.id}）',
        marker: SelfDeclaredMarker.formula,
        declaredTier: impact.tier,
        measuredTier: evidence.derivedTier,
        evidenceId: evidence.id,
      );
    }

    final String note;
    if (evidence != null && !impact.isOverridden) {
      note = '已有实测（${evidence.kind.label}），但还没把先验覆盖掉——'
          '先跑一次 coverWithEvidence';
    } else {
      note = '${impact.source.label}：${impact.tier.label}，'
          '权重 ${_pct(impact.weight)}，未被实测修正';
    }

    return WeightResolution(
      effectiveWeight: impact.weight,
      appliedSource: impact.source,
      declaredWeight: impact.weight,
      priorStillActive: true,
      uiNote: note,
      marker: markerFor(
        cls: measurementClass,
        weight: impact.weight,
        calibrated: false,
      ),
      declaredTier: impact.tier,
      measuredTier: evidence?.derivedTier,
      evidenceId: evidence?.id,
    );
  }

  /// 把证据落账：返回一条 [replacedBy] 指向证据的声明。
  DeclaredImpact coverWithEvidence({
    required DeclaredImpact impact,
    required AnchorEvidence evidence,
  }) =>
      impact.copyWith(replacedBy: evidence.id);

  /// 自声明数据的视觉标记：空心点 + 虚线误差带，宽度随权重（越重越宽，
  /// 表示"这条越值得被校准"）。
  SelfDeclaredMarker markerFor({
    required MeasurementClass cls,
    required double weight,
    required bool calibrated,
  }) {
    if (calibrated) return SelfDeclaredMarker.formula;
    final double base = config.priorBandHalfWidth;
    final double floor = config.priorBandFloorRatio;
    final double ratio = config.priorWeightCap <= 0
        ? floor
        : weight / config.priorWeightCap;
    final double scaled = base * (floor + ratio * (1 - floor));
    return SelfDeclaredMarker(
      hollow: true,
      dashed: true,
      bandHalfWidth: cls == MeasurementClass.formula
          ? scaled
          : scaled * config.subjectiveBandScale,
    );
  }

  // ------------------------------------------------------------ 档位反算

  /// 实测值 → 档位（走系统参照区间）。
  ImpactTier tierFromRange(ReferenceRange range, double measured) =>
      range.bandFor(measured)?.tier ?? ImpactTier.medium;

  /// 实测值 → 档位（无参照区间，按"以你自定义的一次为 1.0"的倍数）。
  ImpactTier tierFromRatio(double measured, {double oneUnit = 1.0}) {
    final ReferenceRange? custom = referenceRangeById('custom');
    if (custom == null) return ImpactTier.medium;
    final double safeUnit = oneUnit <= 0 ? 1 : oneUnit;
    return tierFromRange(custom, measured / safeUnit);
  }

  /// 由一次实测构造证据，并顺手做生理合理性复核。
  ///
  /// 复核不过 → `confidence` 从 calibrated 降到 formula（降置信度，不阻断）。
  AnchorEvidence buildEvidence({
    required String id,
    required String behaviorId,
    required EvidenceKind kind,
    required double measuredValue,
    required String unit,
    required DateTime performedAt,
    ReferenceRange? range,
    MeasurementClass cls = MeasurementClass.formula,
    String note = '',
  }) {
    // 能不能反算档位取决于有没有参照区间，不取决于证据种类——
    // 时间占比同样能落到被动刷手机那张参照表上。
    final ImpactTier tier = range == null
        ? tierFromRatio(measuredValue)
        : tierFromRange(range, measuredValue);

    final SanityVerdict sanity = sanityCheck(
      cls: cls,
      measured: measuredValue,
      range: range,
    );

    final Confidence confidence = sanity.level == SanityLevel.ok
        ? Confidence.calibrated
        : Confidence.formula;

    final String combined = <String>[
      if (note.isNotEmpty) note,
      if (sanity.level != SanityLevel.ok) sanity.note,
    ].join('；');

    return AnchorEvidence(
      id: id,
      behaviorId: behaviorId,
      kind: kind,
      measuredValue: measuredValue,
      unit: unit,
      derivedTier: tier,
      performedAt: performedAt,
      note: combined,
      confidence: confidence,
    );
  }

  // ------------------------------------------------------------ 校验门

  /// 档位调整许可。
  ///
  /// 四条门，顺序不可交换（先解锁、再跳档、最后合理性）：
  ///   1. 「大」未被实测解锁 → 拒绝；
  ///   2. 一次跳超过 [AnchorConfig.tierJumpMax] 档 → 拒绝；
  ///   3. 无证据时把档位往上调 → 允许，但标 downgraded=false 且要求留下理由；
  ///   4. 目标档位是「大」且有证据 → 放行。
  TierChangeVerdict checkTierChange({
    required ImpactTier to,
    ImpactTier? from,
    bool hasCalibratedEvidence = false,
    bool fromEvidence = false,
    String reason = '',
  }) {
    if (to == ImpactTier.large && !hasCalibratedEvidence) {
      return const TierChangeVerdict(
        ok: false,
        code: 'large_locked',
        message: '「大」只能由实测证据解锁。先跑一次校准测试，再回来改这一档。',
      );
    }

    if (from != null && !fromEvidence) {
      final int jump = (to.rank - from.rank).abs();
      if (jump > config.tierJumpMax && !hasCalibratedEvidence) {
        int allowIndex = from.rank + config.tierJumpMax;
        if (allowIndex < 0) allowIndex = 0;
        if (allowIndex > ImpactTier.values.length - 1) {
          allowIndex = ImpactTier.values.length - 1;
        }
        return TierChangeVerdict(
          ok: false,
          code: 'jump_too_far',
          message: '一次最多调 ${config.tierJumpMax} 档（${from.label} → '
              '${ImpactTier.values[allowIndex].label}）。'
              '跨档调整不是不允许，只是要分两步，各留一条理由。',
        );
      }
      if (to.rank > from.rank && reason.trim().isEmpty) {
        return const TierChangeVerdict(
          ok: false,
          code: 'reason_required',
          message: '往上调档要写一句理由——半年后回看才知道当时在想什么。',
        );
      }
    }

    return TierChangeVerdict(
      ok: true,
      code: 'ok',
      message: '已接受。这一档会被写进先验，等实测修正。',
      appliedTier: to,
    );
  }

  /// 生理合理性复核。超常识区间 → 降置信度，**不阻断**。
  SanityVerdict sanityCheck({
    required MeasurementClass cls,
    required double measured,
    ReferenceRange? range,
  }) {
    if (measured <= 0) {
      return SanityVerdict(
        level: SanityLevel.implausible,
        confidencePenalty: config.sanityConfidencePenalty,
        note: '实测值不大于 0，按无效证据处理（不阻断记录）',
      );
    }
    if (range == null) {
      return const SanityVerdict(
        level: SanityLevel.ok,
        confidencePenalty: 0,
        note: '',
      );
    }

    double upper = 0;
    for (final ReferenceBand b in range.bands) {
      if (b.high.isFinite && b.high > upper) upper = b.high;
    }
    if (upper <= 0) {
      return const SanityVerdict(
        level: SanityLevel.ok,
        confidencePenalty: 0,
        note: '',
      );
    }

    final double ratio = measured / upper;
    if (ratio >= config.sanityImplausibleRatio) {
      return SanityVerdict(
        level: SanityLevel.implausible,
        confidencePenalty: config.sanityConfidencePenalty,
        note: '数值超过参照上限 ${ratio.toStringAsFixed(0)} 倍，'
            '按"可能填错单位"处理，这条证据降为推算级',
      );
    }
    if (ratio >= config.sanitySuspectRatio) {
      return SanityVerdict(
        level: SanityLevel.suspect,
        confidencePenalty: config.sanityConfidencePenalty,
        note: '数值明显超出参照区间，先确认单位没串（比如分钟写成小时）',
      );
    }
    return const SanityVerdict(
      level: SanityLevel.ok,
      confidencePenalty: 0,
      note: '',
    );
  }

  // ------------------------------------------------------------ 文案

  /// 「你当初估的是中偏大，实测接近中」——同一句，三处复用。
  String divergenceSentence({
    required ImpactTier declared,
    required ImpactTier measured,
  }) {
    if (declared == measured) {
      return '你当初估的是${declared.label}，实测一致——这条刻度可以停了';
    }
    final String judge;
    if (measured.rank == declared.rank - 1) {
      judge = '第一档';
    } else if (measured.rank < declared.rank) {
      judge = '低 ${declared.rank - measured.rank} 档';
    } else if (measured.rank == declared.rank + 1) {
      judge = '高一档';
    } else {
      judge = '高 ${measured.rank - declared.rank} 档';
    }
    return '你当初估的是${declared.label}，实测接近${measured.label}（$judge）';
  }

  static String _pct(double w) => '${(w * 100).round()}%';

  // ------------------------------------------------------------ 变更范围

  /// 刻度在 [changedAt] 改了：这天之前保持旧刻度，这天起用新的。
  /// **不追溯重算**，只在图上标点。
  RecomputeScope scopeForAnchorChange({
    required DateTime changedAt,
    required String dayKey,
  }) {
    final DateTime? day = DateTime.tryParse(dayKey);
    if (day == null) {
      return const RecomputeScope(
        usesNewScale: true,
        mustMarkPoint: true,
        note: '日期无法解析，按新刻度处理并标点',
      );
    }
    final DateTime dayStart = DateTime(day.year, day.month, day.day);
    final DateTime changedStart =
        DateTime(changedAt.year, changedAt.month, changedAt.day);
    final bool usesNew = !dayStart.isBefore(changedStart);
    return RecomputeScope(
      usesNewScale: usesNew,
      mustMarkPoint: true,
      note: usesNew
          ? '这天起用新刻度'
          : '这天仍按旧刻度计——刻度变更不追溯',
    );
  }
}
