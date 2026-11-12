import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 选项行。整行可点，高度 ≥52，落在单手热区。
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    this.sublabel,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Tokens.motionFast,
      curve: Tokens.motionCurve,
      margin: const EdgeInsets.only(bottom: Tokens.gapS),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: Tokens.fontBody,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (sublabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          sublabel!,
                          style: const TextStyle(
                            fontSize: Tokens.fontCaption,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else
                  AnimatedOpacity(
                    duration: Tokens.motionFast,
                    opacity: selected ? 1 : 0,
                    child: const Icon(Icons.check_rounded,
                        size: 18, color: AppColors.accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小 pill 提示，用于"常规 8–15 次"这类区间信息。
class HintPill extends StatelessWidget {
  const HintPill({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.calmSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.calm),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.calm,
            ),
          ),
        ],
      ),
    );
  }
}

/// "同上次"快捷片。有上次值才显示，点一下直接带入。
class SameAsLastChip extends StatelessWidget {
  const SameAsLastChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.replay_rounded, size: 14, color: AppColors.inkSoft),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
