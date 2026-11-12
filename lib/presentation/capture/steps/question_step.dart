import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/widgets/numeric_step_picker.dart';
import 'package:exp_ledger/presentation/capture/widgets/option_tile.dart';
import 'package:flutter/material.dart';

/// S4：一次只问一件事。
///
/// 屏幕结构固定，用户第二次进来就不用重新学习：
///   进度条 → 问题 → 为什么问 → 回答区 → 区间提示 → 退路
class QuestionStep extends StatefulWidget {
  const QuestionStep({
    super.key,
    required this.controller,
    required this.state,
  });

  final CaptureController controller;
  final CaptureQuestioning state;

  @override
  State<QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends State<QuestionStep> {
  double _number = 0;
  int _minutes = 0;
  String? _questionId;

  @override
  void initState() {
    super.initState();
    _syncWithQuestion();
  }

  @override
  void didUpdateWidget(covariant QuestionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.current?.id != widget.state.current?.id) {
      _syncWithQuestion();
    }
  }

  void _syncWithQuestion() {
    final q = widget.state.current;
    _questionId = q?.id;
    if (q == null) return;
    final spec = q.numberSpec;
    if (spec == null) return;
    final existing = widget.state.answers[q.id];
    if (q.kind == QuestionKind.timeOfDay) {
      _minutes = _minutesFromAnswer(existing, spec.initial.round());
    } else {
      _number = (existing is num)
          ? existing.toDouble()
          : (double.tryParse('${existing ?? ''}') ?? spec.initial);
    }
  }

  int _minutesFromAnswer(Object? answer, int fallback) {
    if (answer is num) return answer.round();
    if (answer is String) {
      final parts = answer.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) return (h * 60 + m) % 1440;
      }
    }
    return fallback;
  }

  String _formatMinutes(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';

  Object? get _lastValue {
    final q = widget.state.current;
    if (q == null) return null;
    return widget.controller.lastAnswersFor(widget.state.behavior.code)?[q.id];
  }

  String _describeLast(Object? v, QuestionSpec q) {
    if (v == null) return '';
    if (v is num) {
      final spec = q.numberSpec;
      final text = spec == null
          ? v.toString()
          : v.toStringAsFixed(spec.decimals) + spec.unit.trim();
      return '同上次：$text';
    }
    final option = q.optionFor('$v');
    if (option != null) return '同上次：${option.label}';
    return '同上次：$v';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final q = s.current;
    if (q == null) return const SizedBox.shrink();

    final issues = s.issues.where((i) => i.questionId == q.id).toList();
    final last = _lastValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressLine(progress: s.progress, step: s.stepNumber, total: s.stepTotal),
        const SizedBox(height: Tokens.gapL),
        Text(
          q.title,
          style: const TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            height: 1.3,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        Text(
          q.why,
          style: const TextStyle(
            fontSize: Tokens.fontSmall,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        if (q.rangeHint != null) ...[
          HintPill(text: q.rangeHint!, icon: Icons.straighten_rounded),
          const SizedBox(height: Tokens.gapM),
        ],
        if (q.inheritFromLast && last != null && !s.usedSameAsLast) ...[
          SameAsLastChip(
            label: _describeLast(last, q),
            onTap: () => widget.controller.dispatch(const UseLastValue()),
          ),
          const SizedBox(height: Tokens.gapM),
        ],
        _buildAnswerArea(q, s),
        if (q.assist != null) ...[
          const SizedBox(height: Tokens.gapM),
          Text(
            q.assist!,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.4,
            ),
          ),
        ],
        if (issues.isNotEmpty) ...[
          const SizedBox(height: Tokens.gapM),
          _SanityBubble(
            issue: issues.first,
            onOverride: () => widget.controller.dispatch(const OverrideSanity()),
          ),
        ],
        const SizedBox(height: Tokens.gapL),
        Row(
          children: [
            if (s.answeredIds.isNotEmpty)
              TextButton.icon(
                onPressed: () => widget.controller.dispatch(const StepBack()),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('上一题'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => widget.controller.dispatch(const MarkUnknown()),
              child: const Text('说不好'),
            ),
          ],
        ),
        if (s.behavior.misconception.isNotEmpty) ...[
          const SizedBox(height: Tokens.gapS),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.behavior.misconception,
                  style: const TextStyle(
                    fontSize: Tokens.fontCaption,
                    color: AppColors.inkFaint,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Tokens.gapM),
      ],
    );
  }

  Widget _buildAnswerArea(QuestionSpec q, CaptureQuestioning s) {
    if (q.kind == QuestionKind.choice) {
      final current = s.answers[q.id];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in q.options)
            OptionTile(
              label: o.label,
              sublabel: o.sublabel,
              selected: current == o.value,
              onTap: () => widget.controller.dispatch(OptionPicked(o.value)),
            ),
        ],
      );
    }

    if (q.kind == QuestionKind.timeOfDay) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TimeStepPicker(
            minutesOfDay: _minutes,
            onChanged: (v) {
              final parts = v.split(':');
              setState(() {
                _minutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
              });
            },
          ),
          const SizedBox(height: Tokens.gapL),
          FilledButton(
            onPressed: () => widget.controller
                .dispatch(TimePicked(_formatMinutes(_minutes))),
            child: const Text('就是这个时间'),
          ),
        ],
      );
    }

    final spec = q.numberSpec!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NumericStepPicker(
          spec: spec,
          value: _number,
          onChanged: (v) => setState(() => _number = v),
        ),
        const SizedBox(height: Tokens.gapL),
        FilledButton(
          onPressed: () => widget.controller.dispatch(NumberChanged(_number)),
          child: const Text('下一步'),
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.progress,
    required this.step,
    required this.total,
  });

  final double progress;
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: Tokens.motionBase,
            curve: Tokens.motionCurve,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 3,
              backgroundColor: AppColors.divider,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '第 $step / $total 步',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 合理性复核气泡：疑问句 + 两个出口，绝不阻断。
class _SanityBubble extends StatelessWidget {
  const _SanityBubble({required this.issue, required this.onOverride});

  final SanityIssue issue;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.calmSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.help_outline_rounded,
                  size: 16, color: AppColors.calm),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.message,
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    color: AppColors.ink,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (issue.suggestion != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                issue.suggestion!,
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOverride,
              child: const Text('我知道我在做什么'),
            ),
          ),
        ],
      ),
    );
  }
}
