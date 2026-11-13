/// 首次标定的引导流程（Step 1–4），渐进式，**一次只问一件事**。
///
/// 三条体验约束，都写进代码而不是文档：
///   1. 只让用户挑真正打算追踪的 3–5 项（[AnchorConfig.minBehaviors]
///      / [AnchorConfig.maxBehaviors]），不是全库；
///   2. 每一步只产出一个 [OnboardingPrompt]，支持「同上次」；
///   3. 标定没做完**不阻塞使用**：没标的行为走自由记录 + 低置信度路径
///      （见 [OnboardingFlow.fallbackConfidence]）。
///
/// 纯函数：给同一个 [OnboardingState]，[OnboardingFlow.next] 永远给同一个下一问。
library;

import '../enums.dart';
import 'anchor_config.dart';
import 'anchor_engine.dart';
import 'anchor_models.dart';
import 'reference_ranges.dart';

enum OnboardingStage {
  pickBehaviors,
  defineUnit,
  declareTier,
  done;

  String get label {
    if (this == OnboardingStage.pickBehaviors) return '选要追踪的行为';
    if (this == OnboardingStage.defineUnit) return '定义单位';
    if (this == OnboardingStage.declareTier) return '声明量级';
    return '刻度卡片';
  }
}

/// 用户挑中的一项行为（还没有单位）。
class OnboardingSelection {
  const OnboardingSelection({
    required this.behaviorId,
    required this.label,
    required this.measurementClass,
    this.hint = '',
  });

  final String behaviorId;
  final String label;
  final MeasurementClass measurementClass;
  final String hint;

  Map<String, Object?> toJson() => <String, Object?>{
        'behavior_id': behaviorId,
        'label': label,
        'measurement_class': measurementClass.name,
        'hint': hint,
      };

  static OnboardingSelection fromJson(Map<String, Object?> json) =>
      OnboardingSelection(
        behaviorId: json['behavior_id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        measurementClass:
            MeasurementClass.parse(json['measurement_class']?.toString() ?? ''),
        hint: json['hint']?.toString() ?? '',
      );
}

class OnboardingState {
  const OnboardingState({
    this.stage = OnboardingStage.pickBehaviors,
    this.selections = const <OnboardingSelection>[],
    this.anchors = const <String, UserAnchor>{},
    this.impacts = const <String, DeclaredImpact>{},
    this.cursor = 0,
    this.usedSameAsLast = false,
    this.abandoned = false,
  });

  final OnboardingStage stage;
  final List<OnboardingSelection> selections;
  final Map<String, UserAnchor> anchors;
  final Map<String, DeclaredImpact> impacts;

  /// 当前正在处理第几项。
  final int cursor;

  final bool usedSameAsLast;

  /// 用户中途退出。已标好的项保留，剩下的走自由记录。
  final bool abandoned;

  OnboardingSelection? get current =>
      cursor >= 0 && cursor < selections.length ? selections[cursor] : null;

  int get doneCount =>
      selections.where((OnboardingSelection s) => anchors.containsKey(s.behaviorId)).length;

  String get progressLabel =>
      '${cursor + 1}/${selections.length}';

  OnboardingState copyWith({
    OnboardingStage? stage,
    List<OnboardingSelection>? selections,
    Map<String, UserAnchor>? anchors,
    Map<String, DeclaredImpact>? impacts,
    int? cursor,
    bool? usedSameAsLast,
    bool? abandoned,
  }) =>
      OnboardingState(
        stage: stage ?? this.stage,
        selections: selections ?? this.selections,
        anchors: anchors ?? this.anchors,
        impacts: impacts ?? this.impacts,
        cursor: cursor ?? this.cursor,
        usedSameAsLast: usedSameAsLast ?? this.usedSameAsLast,
        abandoned: abandoned ?? this.abandoned,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'stage': stage.name,
        'selections':
            selections.map((OnboardingSelection s) => s.toJson()).toList(),
        'anchors': anchors.map((String k, UserAnchor v) =>
            MapEntry<String, Object?>(k, v.toJson())),
        'impacts': impacts.map((String k, DeclaredImpact v) =>
            MapEntry<String, Object?>(k, v.toJson())),
        'cursor': cursor,
        'used_same_as_last': usedSameAsLast,
        'abandoned': abandoned,
      };

  static OnboardingState fromJson(Map<String, Object?> json) {
    final List<Object?> rawSel =
        (json['selections'] as List<Object?>?) ?? const <Object?>[];
    final Map<String, UserAnchor> anchors = <String, UserAnchor>{};
    final Map<String, UserAnchor> readAnchors = _readMap(
      json['anchors'],
      (Map<String, Object?> m) => UserAnchor.fromJson(m),
    );
    anchors.addAll(readAnchors);

    final Map<String, DeclaredImpact> impacts = _readMap(
      json['impacts'],
      (Map<String, Object?> m) => DeclaredImpact.fromJson(m),
    );

    return OnboardingState(
      stage: _stage(json['stage']?.toString() ?? ''),
      selections: rawSel
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) =>
              OnboardingSelection.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
      anchors: anchors,
      impacts: impacts,
      cursor: (json['cursor'] as num?)?.toInt() ?? 0,
      usedSameAsLast: json['used_same_as_last'] == true,
      abandoned: json['abandoned'] == true,
    );
  }

  static OnboardingStage _stage(String raw) {
    for (final OnboardingStage s in OnboardingStage.values) {
      if (s.name == raw) return s;
    }
    return OnboardingStage.pickBehaviors;
  }

  static Map<String, T> _readMap<T>(
    Object? raw,
    T Function(Map<String, Object?>) build,
  ) {
    final Map<String, T> out = <String, T>{};
    if (raw is Map<Object?, Object?>) {
      raw.forEach((Object? k, Object? v) {
        if (k is String && v is Map<Object?, Object?>) {
          out[k] = build(v.cast<String, Object?>());
        }
      });
    }
    return out;
  }
}

enum PromptKind { chooseBehaviors, defineUnit, declareTier, done }

class PromptOption {
  const PromptOption({
    required this.id,
    required this.label,
    this.detail = '',
    this.tier,
    this.unitLabel,
    this.rangeId,
  });

  final String id;
  final String label;
  final String detail;

  /// 档位选项才有。
  final ImpactTier? tier;

  /// 单位选项才有。
  final String? unitLabel;

  /// 参照区间选项才有。
  final String? rangeId;
}

class OnboardingPrompt {
  const OnboardingPrompt({
    required this.kind,
    required this.title,
    required this.question,
    this.behaviorId,
    this.options = const <PromptOption>[],
    this.allowSameAsLast = false,
    this.referenceRange,
    this.footer = '',
  });

  final PromptKind kind;
  final String title;
  final String question;
  final String? behaviorId;
  final List<PromptOption> options;
  final bool allowSameAsLast;

  /// Step 3 要展示给用户的系统参照区间。
  final ReferenceRange? referenceRange;

  /// 回执式脚注：说明"后续会被实测修正"。
  final String footer;
}

class OnboardingFlow {
  const OnboardingFlow(
    this.engine, {
    this.config = kDefaultAnchorConfig,
  });

  final AnchorEngine engine;
  final AnchorConfig config;

  /// 下一问。永远只返回一个问题。
  OnboardingPrompt next(OnboardingState state) {
    if (state.stage == OnboardingStage.done || state.abandoned) {
      return const OnboardingPrompt(
        kind: PromptKind.done,
        title: '刻度卡片已建立',
        question: '以后所有记录都会带上这套刻度。想改随时改，历史不重算。',
        footer: '没标定的行为仍然可以记录：走自由记录 + 低置信度，不影响使用。',
      );
    }

    if (state.stage == OnboardingStage.pickBehaviors) {
      return OnboardingPrompt(
        kind: PromptKind.chooseBehaviors,
        title: '先挑你真正打算追踪的几项',
        question: '不用全选。挑 ${config.minBehaviors}–${config.maxBehaviors} 项，'
            '其余以后再加——选多了会变成填表。',
        footer: '选中后会一项一项问你单位，一次只问一件事。',
      );
    }

    final OnboardingSelection? cur = state.current;
    if (cur == null) {
      return const OnboardingPrompt(
        kind: PromptKind.done,
        title: '刻度卡片已建立',
        question: '这一轮标完了。',
      );
    }

    if (state.stage == OnboardingStage.defineUnit) {
      final List<ReferenceRange> ranges =
          referenceRangesFor(cur.measurementClass);
      final ReferenceRange range = ranges.isEmpty
          ? referenceRangeById('custom')!
          : ranges.first;
      final List<PromptOption> opts = <PromptOption>[
        for (final String u in range.unitSuggestions)
          PromptOption(
            id: 'unit:$u',
            label: '用「$u」',
            detail: range.title,
            unitLabel: u,
            rangeId: range.id,
          ),
        for (final ReferenceRange other in ranges.skip(1))
          PromptOption(
            id: 'range:${other.id}',
            label: '其实更像：${other.title}',
            detail: other.sourceLabel,
            rangeId: other.id,
          ),
      ];
      return OnboardingPrompt(
        kind: PromptKind.defineUnit,
        title: '「${cur.label}」一次是多少   ·   ${state.progressLabel}',
        question: '这件事你怎么数"做了一次"？选一个，也可以自己写。'
            '写完要能事后判断真假——"感觉做了不少"没法校准。',
        behaviorId: cur.behaviorId,
        options: opts,
        allowSameAsLast: state.cursor > 0,
        referenceRange: range,
        footer: '单位是你定的，长期复用。改了会在图上标一个变更点，旧记录不重算。',
      );
    }

    // declareTier
    final UserAnchor? anchor = state.anchors[cur.behaviorId];
    final ReferenceRange? range = anchor == null
        ? referenceRangeById('custom')
        : referenceRangeById(anchor.referenceRangeId);
    final List<PromptOption> tierOpts = <PromptOption>[];
    if (range != null) {
      for (final ReferenceBand b in range.bands) {
        // 「大」先不给：只能由实测解锁。
        if (b.tier == ImpactTier.large) continue;
        tierOpts.add(PromptOption(
          id: 'tier:${b.tier.name}',
          label: '${b.tier.label} · ${b.note}',
          detail: _bandLine(b, range),
          tier: b.tier,
        ));
      }
      tierOpts.add(PromptOption(
        id: 'tier:${ImpactTier.large.name}',
        label: '大 · 会改变接下来几天的主要安排',
        detail: '需要一次实测才能选这一档',
        tier: ImpactTier.large,
      ));
    }
    return OnboardingPrompt(
      kind: PromptKind.declareTier,
      title: '「${cur.label}」有多重   ·   ${state.progressLabel}',
      question: '以你刚定的「${anchor?.unitLabel ?? '一次'}」为单位，'
          '这件事对你的影响在哪个量级？',
      behaviorId: cur.behaviorId,
      options: tierOpts,
      allowSameAsLast: state.cursor > 0,
      referenceRange: range,
      footer: '这只是先验，权重不超过 '
          '${(config.priorWeightCap * 100).round()}%。'
          '之后有实测证据会自动覆盖，并在图上告诉你差了几档。',
    );
  }

  static String _bandLine(ReferenceBand b, ReferenceRange r) {
    final String unit =
        r.unitSuggestions.isEmpty ? '' : r.unitSuggestions.first;
    if (b.high.isFinite) {
      return '参照区间 ${_fmt(b.low)}–${_fmt(b.high)} $unit';
    }
    return '参照区间 ${_fmt(b.low)} $unit 以上';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  // ------------------------------------------------------------ 状态推进

  OnboardingState pickBehaviors(
    OnboardingState state,
    List<OnboardingSelection> picked,
  ) {
    final List<OnboardingSelection> capped = picked
        .take(config.maxBehaviors)
        .toList(growable: false);
    return state.copyWith(
      stage: capped.isEmpty
          ? OnboardingStage.pickBehaviors
          : OnboardingStage.defineUnit,
      selections: capped,
      cursor: 0,
    );
  }

  OnboardingState defineUnit(
    OnboardingState state, {
    required DateTime at,
    String? unitLabel,
    String definitionText = '',
    String referenceObject = '',
    String? rangeId,
    bool sameAsLast = false,
  }) {
    final OnboardingSelection? cur = state.current;
    if (cur == null) return state;

    String unit = unitLabel?.trim() ?? '';
    String def = definitionText.trim();
    String ref = referenceObject.trim();

    // 没显式选参照区间时先挂 custom，但**不改这一项的分类**——
    // 分类只在用户明确点选另一个区间时才随区间走。
    bool rangeExplicit = rangeId != null && rangeId.trim().isNotEmpty;
    String range = rangeExplicit ? rangeId.trim() : 'custom';

    if (sameAsLast && state.cursor > 0) {
      final UserAnchor? prev = state.anchors[state.selections[state.cursor - 1].behaviorId];
      if (prev != null) {
        unit = prev.unitLabel;
        def = prev.definitionText;
        ref = prev.referenceObject;
        range = prev.referenceRangeId;
        rangeExplicit = true;
      }
    }

    if (unit.isEmpty) {
      // 空单位不允许落账：§"未完成标定不阻塞使用"走的是另一条路，
      // 不是"允许空单位进卡片"。
      return state;
    }

    final ReferenceRange? r = referenceRangeById(range);
    final UserAnchor anchor = UserAnchor(
      behaviorId: cur.behaviorId,
      unitLabel: unit,
      definitionText: def.isEmpty ? '一次$unit' : def,
      referenceObject: ref,
      measurementClass: cur.measurementClass,
      referenceRangeId: range,
      calibratedAt: at,
      revisionHistory: const <AnchorRevision>[],
    );

    final Map<String, UserAnchor> nextAnchors =
        Map<String, UserAnchor>.unmodifiable(<String, UserAnchor>{
      ...state.anchors,
      cur.behaviorId: anchor,
    });

    // 只有在用户明确选了区间、且该区间的分类与行为分类不同时，才以区间为准。
    final MeasurementClass cls = (r != null && rangeExplicit)
        ? r.measurementClass
        : cur.measurementClass;

    return state.copyWith(
      stage: OnboardingStage.declareTier,
      anchors: nextAnchors,
      usedSameAsLast: state.usedSameAsLast || sameAsLast,
      selections: cls == cur.measurementClass
          ? state.selections
          : <OnboardingSelection>[
              for (int i = 0; i < state.selections.length; i++)
                if (i == state.cursor)
                  OnboardingSelection(
                    behaviorId: cur.behaviorId,
                    label: cur.label,
                    measurementClass: cls,
                    hint: cur.hint,
                  )
                else
                  state.selections[i],
            ],
    );
  }

  /// 返回 (新状态, 判定)。判定被拒时状态不变。
  ({
    OnboardingState state,
    TierChangeVerdict verdict,
  }) declareTier(
    OnboardingState state, {
    required DateTime at,
    required ImpactTier tier,
    bool sameAsLast = false,
    String reason = '',
  }) {
    final OnboardingSelection? cur = state.current;
    if (cur == null) {
      return (
        state: state,
        verdict: const TierChangeVerdict(
          ok: false,
          code: 'no_behavior',
          message: '当前没有待标定的行为',
        ),
      );
    }

    ImpactTier applied = tier;
    if (sameAsLast && state.cursor > 0) {
      final DeclaredImpact? prev =
          state.impacts[state.selections[state.cursor - 1].behaviorId];
      if (prev != null) applied = prev.tier;
    }

    final TierChangeVerdict verdict = engine.checkTierChange(
      to: applied,
      hasCalibratedEvidence: false,
      reason: reason,
    );
    if (!verdict.ok) {
      return (state: state, verdict: verdict);
    }

    final DeclaredImpact impact = engine.declare(
      behaviorId: cur.behaviorId,
      tier: applied,
      source: ImpactSource.userPrior,
      at: at,
      note: reason,
    );

    final Map<String, DeclaredImpact> nextImpacts =
        Map<String, DeclaredImpact>.unmodifiable(<String, DeclaredImpact>{
      ...state.impacts,
      cur.behaviorId: impact,
    });

    final int nextCursor = state.cursor + 1;
    final bool finished = nextCursor >= state.selections.length;
    final Map<String, UserAnchor> nextAnchors = state.anchors;

    return (
      state: state.copyWith(
        stage: finished ? OnboardingStage.done : OnboardingStage.defineUnit,
        impacts: nextImpacts,
        cursor: finished ? state.cursor : nextCursor,
        usedSameAsLast: state.usedSameAsLast || sameAsLast,
        anchors: nextAnchors,
      ),
      verdict: TierChangeVerdict(
        ok: true,
        code: 'ok',
        message: '记下了：${applied.label}。'
            '这一档现在只是先验，实测会修正它。',
        appliedTier: applied,
      ),
    );
  }

  /// 用户中途退出：保留已标好的，剩下走自由记录。
  OnboardingState abandon(OnboardingState state) =>
      state.copyWith(abandoned: true, stage: OnboardingStage.done);

  // ------------------------------------------------------------ 产物

  /// Step 4：个人刻度卡片。
  List<AnchorCard> buildCards(OnboardingState state, {
    Map<String, AnchorEvidence> evidences = const <String, AnchorEvidence>{},
  }) {
    final List<AnchorCard> out = <AnchorCard>[];
    for (final OnboardingSelection s in state.selections) {
      final UserAnchor? a = state.anchors[s.behaviorId];
      final DeclaredImpact? i = state.impacts[s.behaviorId];
      if (a == null || i == null) continue;
      out.add(AnchorCard(
        behaviorId: s.behaviorId,
        anchor: a,
        impact: i,
        evidence: evidences[s.behaviorId],
      ));
    }
    return out;
  }

  /// 这条行为有没有完成标定。
  bool isCalibrated(OnboardingState state, String behaviorId) =>
      state.anchors.containsKey(behaviorId) &&
      state.impacts.containsKey(behaviorId);

  /// 记录本体的置信度：**标定不等于校准**。
  ///
  /// 标定只解决"怎么量"（单位 + 档位），不改变这条记录的可信度——所以
  /// 标定完成的记录依然是 [Confidence.selfReport]，直到次日确认闭环或
  /// 实测证据把它顶上去。未标定行为走同一条路，因此"没标完"不挡记录。
  Confidence recordConfidence(String behaviorId) => Confidence.selfReport;
}
