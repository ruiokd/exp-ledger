import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/capture/receipt_builder.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/behavior_def.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/widgets/confidence_badge.dart';
import 'package:flutter/material.dart';

/// S5：即时换算回执。
///
/// 这一屏是整个产品的信任基础：必须在用户点"就这样"之前，
/// 把"系统到底理解成了什么"讲清楚，且允许一键撤回。
class ReceiptStep extends StatelessWidget {
  const ReceiptStep({
    super.key,
    required this.controller,
    required this.state,
    this.receiptBuilder = const ReceiptBuilder(),
  });

  final CaptureController controller;
  final CaptureReceipting state;
  final ReceiptBuilder receiptBuilder;

  @override
  Widget build(BuildContext context) {
    final valence = state.valence;
    final view = receiptBuilder.build(
      behavior: state.behavior,
      derived: state.derived,
      valence: valence,
    );
    final accent = switch (valence) {
      Valence.negative => AppColors.negative,
      Valence.offPlan => AppColors.neutral,
      _ => AppColors.accent,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              receiptBuilder.headerFor(valence),
              style: const TextStyle(
                fontSize: Tokens.fontSmall,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            ConfidenceBadge(confidence: view.confidence),
          ],
        ),
        const SizedBox(height: Tokens.gapM),
        Text(
          view.interpretation,
          style: const TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            height: 1.35,
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < view.lines.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _LineRow(line: view.lines[i], accent: accent),
              ],
            ],
          ),
        ),
        const SizedBox(height: Tokens.gapM),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            view.confidenceLine,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
        ),
        for (final note in view.notes)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkSoft,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (final warning in view.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.calmSoft,
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 15, color: AppColors.calm),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Tokens.gapXl),
        FilledButton(
          onPressed: () => controller.dispatch(const ConfirmReceipt()),
          child: const Text('就这样'),
        ),
        const SizedBox(height: Tokens.gapS),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => controller.dispatch(const EditReceipt()),
                child: const Text('改一下'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => controller.dispatch(const Abort()),
                child: const Text('撤销本次'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.gapS),
        Center(
          child: Text(
            view.footnote,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: Tokens.gapM),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.accent});

  final ReceiptLine line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            line.label,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkFaint,
            ),
          ),
        ),
        Expanded(
          child: Text(
            line.value,
            style: TextStyle(
              fontSize: line.emphasis ? Tokens.fontBody : Tokens.fontSmall,
              color: line.emphasis ? AppColors.ink : AppColors.inkSoft,
              fontWeight: line.emphasis ? FontWeight.w600 : FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
