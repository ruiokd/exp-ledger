/// 「怎么折算」的四选一。
///
/// 从 `new_behavior_page.dart` 切出来的：它不只属于新建页，
/// 将来的口径编辑页、刻度页的"改一下折算方式"用的是同一个控件。
/// 一个控件在两处各写一遍，就会得到两种措辞不一致的解释文案。
library;

import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:flutter/material.dart';

class ShapePicker extends StatelessWidget {
  const ShapePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = '怎么折算',
    this.hint = '目标量处一律算满分；这里选的是"没做满时算几成"。',
    this.enabled = true,
  });

  final DoseShape value;
  final ValueChanged<DoseShape> onChanged;
  final String title;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: Tokens.fontBody, color: AppColors.ink),
        ),
        const SizedBox(height: Tokens.gapXs),
        Text(
          hint,
          style: const TextStyle(
            fontSize: Tokens.fontMicro,
            color: AppColors.inkFaint,
            height: 1.4,
          ),
        ),
        const SizedBox(height: Tokens.gapXs),
        Wrap(
          spacing: Tokens.gapXs,
          runSpacing: Tokens.gapXs,
          children: DoseShape.values.map((DoseShape shape) {
            final bool selected = value == shape;
            return ChoiceChip(
              label: Text(
                shape.label,
                style: TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: selected ? AppColors.surface : AppColors.ink,
                ),
              ),
              selected: selected,
              selectedColor: AppColors.accent,
              backgroundColor: AppColors.surface,
              onSelected:
                  enabled ? (bool _) => onChanged(shape) : null,
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: Tokens.gapXs),
        Text(
          value.semantics,
          style: const TextStyle(
            fontSize: Tokens.fontMicro,
            color: AppColors.calm,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
