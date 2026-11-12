import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';

import 'capture_state.dart';
import 'intent_matcher.dart';
import 'sanity_checker.dart';

/// 状态机需要的全部外部依赖。全部用函数注入，方便测试时换成假时钟。
class CaptureDeps {
  const CaptureDeps({
    required this.library,
    required this.matcher,
    required this.profile,
    required this.config,
    required this.now,
    required this.newSessionId,
    this.lastAnswers,
    this.sanity = const SanityChecker(),
  });

  final BehaviorLibrary library;
  final IntentMatcher matcher;
  final UserProfile Function() profile;
  final BalanceConfig Function() config;
  final DateTime Function() now;
  final String Function() newSessionId;

  /// 上一次同行为的归一化答案，用于"同上次"。
  final Map<String, Object?>? Function(String behaviorCode)? lastAnswers;

  final SanityChecker sanity;
}

/// 采集事件。
sealed class CaptureEvent {
  const CaptureEvent();
}

final class TextChanged extends CaptureEvent {
  const TextChanged(this.text);

  final String text;
}

final class VoiceResult extends CaptureEvent {
  const VoiceResult(this.text);

  final String text;
}

final class SubmitIntent extends CaptureEvent {
  const SubmitIntent();
}

final class CandidatePicked extends CaptureEvent {
  const CandidatePicked(this.index);

  final int index;
}

final class PickByCode extends CaptureEvent {
  const PickByCode(this.code);

  final String code;
}

final class PlanAnswered extends CaptureEvent {
  const PlanAnswered(this.status);

  final PlanStatus status;
}

final class OptionPicked extends CaptureEvent {
  const OptionPicked(this.value);

  final String value;
}

final class NumberChanged extends CaptureEvent {
  const NumberChanged(this.value);

  final double value;
}

final class TimePicked extends CaptureEvent {
  const TimePicked(this.hhmm);

  final String hhmm;
}

/// 当前这道题用上次的值。
final class UseLastValue extends CaptureEvent {
  const UseLastValue();
}

/// 整个行为"和上次一样"。
final class UseLastAnswers extends CaptureEvent {
  const UseLastAnswers();
}

/// 当前这道题答"不确定"，不阻塞。
final class MarkUnknown extends CaptureEvent {
  const MarkUnknown();
}

final class StepBack extends CaptureEvent {
  const StepBack();
}

final class JumpToQuestion extends CaptureEvent {
  const JumpToQuestion(this.questionId);

  final String questionId;
}

final class OverrideSanity extends CaptureEvent {
  const OverrideSanity();
}

final class ConfirmReceipt extends CaptureEvent {
  const ConfirmReceipt();
}

final class EditReceipt extends CaptureEvent {
  const EditReceipt();
}

final class Abort extends CaptureEvent {
  const Abort();
}

/// 采集状态机。纯函数：reduce(state, event) → state。
///
/// 不碰数据库、不碰 UI、不碰时间——时间从 deps.now 拿。
/// 因此整套流程可以在单元测试里被完整走一遍。
class CaptureMachine {
  const CaptureMachine(this.deps);

  final CaptureDeps deps;

  CaptureState reduce(CaptureState state, CaptureEvent event) {
    if (event is Abort) return const CaptureAborted();

    // ---------------------------------------------------------- S0 空闲
    // 打开采集窗口时状态是 Idle，第一次输入直接进入意图输入态，
    // 这样 UI 不需要额外发一个"开始"事件。
    if (state is CaptureIdle) {
      if (event is TextChanged) return CaptureIntentInput(event.text);
      if (event is VoiceResult) {
        final text = event.text.trim();
        if (text.isNotEmpty) return _resolveIntent(text);
      }
      if (event is PickByCode) {
        final b = deps.library.byCode(event.code);
        if (b != null) return _enterBehavior(b, const {});
      }
    }

    // ---------------------------------------------------------- S1 意图输入
    if (state is CaptureIntentInput) {
      if (event is TextChanged) return CaptureIntentInput(event.text);
      if (event is VoiceResult) {
        final text = event.text.trim();
        return text.isEmpty ? state : _resolveIntent(text);
      }
      if (event is SubmitIntent) {
        final text = state.text.trim();
        if (text.isEmpty) return const CaptureAborted();
        return _resolveIntent(text);
      }
      if (event is StepBack) return const CaptureAborted();
    }

    // ---------------------------------------------------------- S2 候选卡
    if (state is CaptureDisambiguating) {
      if (event is CandidatePicked) {
        if (event.index < 0 || event.index >= state.candidates.length) {
          return state;
        }
        final c = state.candidates[event.index];
        return _enterBehavior(c.behavior, c.prefill);
      }
      if (event is PickByCode) {
        final b = deps.library.byCode(event.code);
        if (b == null) return state;
        return _enterBehavior(b, const {});
      }
      if (event is TextChanged) return CaptureIntentInput(event.text);
      if (event is StepBack) return CaptureIntentInput(state.text);
    }

    // ---------------------------------------------------------- S3 计划门
    if (state is CapturePlanGate) {
      if (event is PlanAnswered) {
        return _startQuestions(
          state.behavior,
          {...state.answers},
          state.prefill.keys.toList(),
          planStatus: event.status,
        );
      }
      if (event is StepBack) {
        return CaptureDisambiguating(
          text: '',
          candidates: [MatchResult(
            behavior: state.behavior,
            score: 1,
            hits: [state.behavior.name],
          )],
        );
      }
    }

    // ---------------------------------------------------------- S4 问答
    if (state is CaptureQuestioning) {
      final q = state.current;
      if (event is OptionPicked && q != null) {
        return _commitValue(state, event.value);
      }
      if (event is NumberChanged && q != null) return _commitValue(state, event.value);
      if (event is TimePicked && q != null) return _commitValue(state, event.hhmm);
      if (event is MarkUnknown && q != null) {
        return _commitValue(state, kUnknownValue);
      }
      if (event is UseLastValue && q != null) {
        final last = deps.lastAnswers?.call(state.behavior.code);
        final v = last?[q.id];
        if (v == null) return state;
        return _commitValue(state, v);
      }
      if (event is UseLastAnswers) return _applyLastAnswers(state);
      if (event is OverrideSanity) {
        return state.copyWith(
          issues: const [],
          showingOverrideHint: true,
        );
      }
      if (event is StepBack) return _stepBack(state);
      if (event is JumpToQuestion) return _jumpTo(state, event.questionId);
    }

    // ---------------------------------------------------------- S5 回执
    if (state is CaptureReceipting) {
      if (event is ConfirmReceipt) {
        return CaptureCommitted(_buildEntry(state));
      }
      if (event is EditReceipt) {
        return CaptureQuestioning(
          behavior: state.behavior,
          answers: {...state.answers},
          answeredIds: const [],
          ceiling: state.ceiling,
        );
      }
      if (event is StepBack) {
        return CaptureQuestioning(
          behavior: state.behavior,
          answers: {...state.answers},
          answeredIds: state.behavior.questions
              .where((q) => state.answers.containsKey(q.id))
              .map((q) => q.id)
              .toList(),
          ceiling: state.ceiling,
        );
      }
    }

    return state;
  }

  // ---------------------------------------------------------------- 内部

  CaptureState _resolveIntent(String text) {
    final candidates = deps.matcher.match(text);
    if (candidates.isEmpty) return CaptureFreeform(text);
    return CaptureDisambiguating(text: text, candidates: candidates);
  }

  CaptureState _enterBehavior(BehaviorDef behavior, Map<String, String> prefill) {
    final answers = <String, Object?>{...prefill};
    if (behavior.needsPlanGate) {
      return CapturePlanGate(
        behavior: behavior,
        answers: answers,
        prefill: prefill,
      );
    }
    return _startQuestions(behavior, answers, prefill.keys.toList());
  }

  CaptureState _startQuestions(
    BehaviorDef behavior,
    Map<String, Object?> answers,
    List<String> answeredIds, {
    PlanStatus planStatus = PlanStatus.planned,
  }) {
    final state = CaptureQuestioning(
      behavior: behavior,
      answers: answers,
      answeredIds: answeredIds,
      planStatus: planStatus,
    );
    return _settle(state);
  }

  /// 如果所有可见问题都答完了，直接进回执。
  CaptureState _settle(CaptureQuestioning state) {
    if (!state.isComplete) return state;
    final answers = _withDefaults(state.behavior, state.answers);
    final derived = _derive(state.behavior, answers, state.ceiling);
    return CaptureReceipting(
      behavior: state.behavior,
      answers: answers,
      derived: derived,
      planStatus: state.planStatus,
      sessionId: deps.newSessionId(),
      ceiling: state.ceiling,
    );
  }

  CaptureState _commitValue(CaptureQuestioning state, Object? value) {
    final q = state.current;
    if (q == null) return state;
    final answers = <String, Object?>{...state.answers, q.id: value};
    final answered = <String>[...state.answeredIds, q.id];
    final ceiling = value == kUnknownValue
        ? Confidence.selfReport
        : state.ceiling;
    final issues = deps.sanity.check(
      behavior: state.behavior,
      answers: answers,
      profile: deps.profile(),
    );
    return _settle(
      state.copyWith(
        answers: answers,
        answeredIds: answered,
        ceiling: ceiling,
        issues: issues,
        showingOverrideHint: false,
      ),
    );
  }

  CaptureState _applyLastAnswers(CaptureQuestioning state) {
    final last = deps.lastAnswers?.call(state.behavior.code);
    if (last == null || last.isEmpty) return state;
    final answers = <String, Object?>{...state.answers, ...last};
    final answered = <String>[...state.answeredIds];
    for (final q in state.behavior.questions) {
      if (last.containsKey(q.id) && !answered.contains(q.id)) {
        answered.add(q.id);
      }
    }
    return _settle(
      state.copyWith(
        answers: answers,
        answeredIds: answered,
        usedSameAsLast: true,
      ),
    );
  }

  CaptureState _stepBack(CaptureQuestioning state) {
    if (state.answeredIds.isEmpty) return state;
    final lastId = state.answeredIds.last;
    final answers = <String, Object?>{...state.answers}..remove(lastId);
    return state.copyWith(
      answers: answers,
      answeredIds: state.answeredIds.sublist(0, state.answeredIds.length - 1),
      issues: const [],
    );
  }

  CaptureState _jumpTo(CaptureQuestioning state, String questionId) {
    final visible = state.visibleQuestions;
    final idx = visible.indexWhere((q) => q.id == questionId);
    if (idx < 0) return state;
    final before = visible.take(idx).map((q) => q.id).toList();
    return state.copyWith(answeredIds: before, issues: const []);
  }

  /// 给缺失的数值题填默认值，保证 derive 拿到的是完整 map。
  Map<String, Object?> _withDefaults(
    BehaviorDef behavior,
    Map<String, Object?> answers,
  ) {
    final result = <String, Object?>{...answers};
    for (final q in behavior.questions) {
      if (result.containsKey(q.id)) continue;
      if (!q.isVisible(result)) continue;
      final spec = q.numberSpec;
      if (spec == null) continue;
      if (q.kind == QuestionKind.timeOfDay) {
        final m = spec.initial.round();
        final hh = (m ~/ 60).toString().padLeft(2, '0');
        final mm = (m % 60).toString().padLeft(2, '0');
        result[q.id] = '$hh:$mm';
      } else {
        result[q.id] = spec.initial;
      }
    }
    return result;
  }

  DerivedResult _derive(
    BehaviorDef behavior,
    Map<String, Object?> answers,
    Confidence ceiling,
  ) {
    final ctx = DeriveContext(
      answers: answers,
      profile: deps.profile(),
      config: deps.config(),
      now: deps.now(),
      lastAnswers: deps.lastAnswers?.call(behavior.code),
      confidenceCeiling: ceiling,
    );
    return behavior.derive(ctx);
  }

  /// 确认后才落库。这里是"唯一写入口"的前半段，真正的 SQL 在仓储层。
  DraftEntry _buildEntry(CaptureReceipting state) {
    final now = deps.now();
    return DraftEntry.fromDerived(
      dayKey: DayKey.fromDate(now),
      behavior: state.behavior,
      derived: state.derived,
      planStatus: state.planStatus,
      now: now,
      sessionId: state.sessionId,
    );
  }
}

/// 约定：计划外行为在选择"临时加的"之后才走超额通道。
/// 这个函数给 UI 一个统一的判断口径。
bool requiresPlanStatus(BehaviorDef b) => b.needsPlanGate;
