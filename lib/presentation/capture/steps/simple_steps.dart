import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/capture/intent_matcher.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/widgets/option_tile.dart';
import 'package:flutter/material.dart';

/// S2：候选卡片。最多三张，第一张默认高亮。
class DisambiguateStep extends StatelessWidget {
  const DisambiguateStep({
    super.key,
    required this.controller,
    required this.state,
  });

  final CaptureController controller;
  final CaptureDisambiguating state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Tokens.gapS),
        const Text(
          '你说的是这个吗？',
          style: TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        Text(
          '「${state.text}」',
          style: const TextStyle(
            fontSize: Tokens.fontBody,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        for (var i = 0; i < state.candidates.length; i++)
          _CandidateCard(
            index: i,
            result: state.candidates[i],
            isTop: i == 0,
            onTap: () => controller.dispatch(CandidatePicked(i)),
          ),
        const SizedBox(height: Tokens.gapS),
        TextButton.icon(
          onPressed: () => controller.dispatch(const Abort()),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('都不是，我自由记录'),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.index,
    required this.result,
    required this.isTop,
    required this.onTap,
  });

  final int index;
  final MatchResult result;
  final bool isTop;
  final VoidCallback onTap;

  Color get _dot => switch (result.behavior.valence) {
        Valence.negative => AppColors.negative,
        Valence.offPlan => AppColors.neutral,
        _ => AppColors.accent,
      };

  @override
  Widget build(BuildContext context) {
    final behavior = result.behavior;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.gapM),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(color: _dot, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        behavior.name,
                        style: const TextStyle(
                          fontSize: Tokens.fontTitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isTop)
                        const HintPill(text: '最像'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    behavior.standardDefinition,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkSoft,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '听到了「${result.hits.take(2).join('、')}」',
                    style: const TextStyle(
                      fontSize: Tokens.fontNano,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// S3：计划门。三个选项，一次点击，不解释。
class PlanGateStep extends StatelessWidget {
  const PlanGateStep({
    super.key,
    required this.controller,
    required this.state,
  });

  final CaptureController controller;
  final CapturePlanGate state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Tokens.gapS),
        const Text(
          '这件事在你计划里吗？',
          style: TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        Text(
          '答案会决定它算"完成"、"超额"还是"中断"，不影响你怎么被评价。',
          style: const TextStyle(
            fontSize: Tokens.fontSmall,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
        const SizedBox(height: Tokens.gapXl),
        for (final status in PlanStatus.values)
          OptionTile(
            label: status.label,
            sublabel: switch (status) {
              PlanStatus.planned => '本来就打算做',
              PlanStatus.offPlan => '计划外多做的，会按边际递减计',
              PlanStatus.missed => '计划里写了，但没做',
            },
            onTap: () => controller.dispatch(PlanAnswered(status)),
          ),
      ],
    );
  }
}

/// S7：自由记录。什么都匹配不上时也绝不丢数据。
class FreeformStep extends StatelessWidget {
  const FreeformStep({
    super.key,
    required this.controller,
    required this.state,
  });

  final CaptureController controller;
  final CaptureFreeform state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Tokens.gapS),
        const Text(
          '没太听懂，但我不想漏掉它',
          style: TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        const Text(
          '先原样记下来，48 小时内可以补全细节。补全之前它只算"低置信度记录"，不参与加减分。',
          style: TextStyle(
            fontSize: Tokens.fontSmall,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        SoftCard(
          color: AppColors.surfaceMuted,
          child: Text(
            state.text,
            style: const TextStyle(
              fontSize: Tokens.fontBody,
              color: AppColors.ink,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        FilledButton(
          onPressed: () => controller.dispatch(const Abort()),
          child: const Text('存下来，稍后补'),
        ),
        const SizedBox(height: Tokens.gapS),
        TextButton(
          onPressed: () => controller.dispatch(const Abort()),
          child: const Text('算了，重新说'),
        ),
      ],
    );
  }
}
