import 'package:exp_ledger/domain/enums.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// 置信度小标记。三种来源用三种颜色，但都不刺眼。
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.compact = false,
  });

  final Confidence confidence;
  final bool compact;

  Color get _color => switch (confidence) {
        Confidence.calibrated => AppColors.confidenceCalibrated,
        Confidence.formula => AppColors.confidenceFormula,
        Confidence.selfReport => AppColors.confidenceSelfReport,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(Tokens.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            confidence.badgeLabel,
            style: TextStyle(
              fontSize: compact ? 11 : Tokens.fontCaption,
              color: _color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
