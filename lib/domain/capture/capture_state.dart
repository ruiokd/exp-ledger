import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';

import 'intent_matcher.dart';

/// 采集窗口的状态。全部是不可变值对象，UI 直接按类型 switch 渲染。
sealed class CaptureState {
  const CaptureState();
}

/// 未开始。
final class CaptureIdle extends CaptureState {
  const CaptureIdle();
}

/// S1：用户正在说人话。
final class CaptureIntentInput extends CaptureState {
  const CaptureIntentInput(this.text);

  final String text;
}

/// S2：候选卡片。
final class CaptureDisambiguating extends CaptureState {
  const CaptureDisambiguating({
    required this.text,
    required this.candidates,
  });

  final String text;
  final List<MatchResult> candidates;

  bool get isEmpty => candidates.isEmpty;
}

/// S3：计划门。
final class CapturePlanGate extends CaptureState {
  const CapturePlanGate({
    required this.behavior,
    this.answers = const {},
    this.prefill = const {},
  });

  final BehaviorDef behavior;
  final Map<String, Object?> answers;
  final Map<String, String> prefill;
}

/// S4：一次一屏的问答。
final class CaptureQuestioning extends CaptureState {
  const CaptureQuestioning({
    required this.behavior,
    required this.answers,
    required this.answeredIds,
    this.ceiling = Confidence.calibrated,
    this.usedSameAsLast = false,
    this.issues = const [],
    this.showingOverrideHint = false,
    this.planStatus = PlanStatus.planned,
  });

  final BehaviorDef behavior;
  final Map<String, Object?> answers;
  final List<String> answeredIds;
  final Confidence ceiling;
  final bool usedSameAsLast;

  /// 用户在计划门选的结果，一路带到回执与结算。
  final PlanStatus planStatus;

  /// 当前值触发的合理性复核提示（不阻断）。
  final List<SanityIssue> issues;

  /// 用户选了"我知道我在做什么"后，复核气泡不再重复弹出。
  final bool showingOverrideHint;

  List<QuestionSpec> get visibleQuestions {
    final list = behavior.questions.where((q) => q.isVisible(answers)).toList();
    return list;
  }

  QuestionSpec? get current {
    for (final q in visibleQuestions) {
      if (!answeredIds.contains(q.id)) return q;
    }
    return null;
  }

  bool get isComplete => current == null;

  double get progress {
    final total = visibleQuestions.length;
    if (total == 0) return 1;
    final done = answeredIds.where(
      (id) => visibleQuestions.any((q) => q.id == id),
    ).length;
    return (done / total).clamp(0, 1).toDouble();
  }

  int get stepNumber => answeredIds.length + 1;

  int get stepTotal => visibleQuestions.length;

  CaptureQuestioning copyWith({
    Map<String, Object?>? answers,
    List<String>? answeredIds,
    Confidence? ceiling,
    bool? usedSameAsLast,
    List<SanityIssue>? issues,
    bool? showingOverrideHint,
    PlanStatus? planStatus,
  }) {
    return CaptureQuestioning(
      behavior: behavior,
      answers: answers ?? this.answers,
      answeredIds: answeredIds ?? this.answeredIds,
      ceiling: ceiling ?? this.ceiling,
      usedSameAsLast: usedSameAsLast ?? this.usedSameAsLast,
      issues: issues ?? this.issues,
      showingOverrideHint: showingOverrideHint ?? this.showingOverrideHint,
      planStatus: planStatus ?? this.planStatus,
    );
  }
}

/// S5：即时换算回执，等用户确认。
final class CaptureReceipting extends CaptureState {
  const CaptureReceipting({
    required this.behavior,
    required this.answers,
    required this.derived,
    required this.planStatus,
    required this.sessionId,
    this.ceiling = Confidence.calibrated,
  });

  final BehaviorDef behavior;
  final Map<String, Object?> answers;
  final DerivedResult derived;
  final PlanStatus planStatus;
  final String sessionId;
  final Confidence ceiling;

  Valence get valence => behavior.valenceOf(derived);
}

/// S6：已落库。
final class CaptureCommitted extends CaptureState {
  const CaptureCommitted(this.entry);

  final DraftEntry entry;
}

/// S7：自由记录兜底。
final class CaptureFreeform extends CaptureState {
  const CaptureFreeform(this.text);

  final String text;
}

/// 退出。
final class CaptureAborted extends CaptureState {
  const CaptureAborted();
}

/// 合理性复核提示。soft=true 表示只提示、可继续。
class SanityIssue {
  const SanityIssue({
    required this.questionId,
    required this.message,
    this.soft = true,
    this.suggestion,
  });

  final String questionId;
  final String message;
  final bool soft;
  final String? suggestion;
}
