import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/models/capture_question.dart';
import 'package:flutter/material.dart';

/// 大号数字步进器。加减按钮在两侧，双手/单手持握都够得到。
///
/// 设计要点：
///   · 主值是屏幕视觉重心，一眼能确认自己填的是不是想要的。
///   · 常用值做成 chip，一步到位，不用连点十次。
///   · 键盘输入是最后一个选项（点数字本身才唤起）。
class NumericStepPicker extends StatelessWidget {
  const NumericStepPicker({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final NumberSpec spec;
  final double value;
  final ValueChanged<double> onChanged;
  final String? label;

  double _clamp(double v) => v < spec.min ? spec.min : (v > spec.max ? spec.max : v);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(
            label!,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkFaint,
            ),
          ),
        const SizedBox(height: Tokens.gapM),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: () => onChanged(_clamp(value - spec.step)),
            ),
            GestureDetector(
              onTap: () => _openKeypad(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.toStringAsFixed(spec.decimals),
                    style: const TextStyle(
                      fontSize: Tokens.fontHeroLarge,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.1,
                    ),
                  ),
                  if (spec.unit.trim().isNotEmpty)
                    Text(
                      spec.unit.trim(),
                      style: const TextStyle(
                        fontSize: Tokens.fontSmall,
                        color: AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: () => onChanged(_clamp(value + spec.step)),
            ),
          ],
        ),
        if (spec.presets.isNotEmpty) ...[
          const SizedBox(height: Tokens.gapL),
          Wrap(
            spacing: Tokens.gapS,
            runSpacing: Tokens.gapS,
            alignment: WrapAlignment.center,
            children: [
              for (final p in spec.presets)
                _PresetChip(
                  text: '${p.toStringAsFixed(spec.decimals)}',
                  selected: (p - value).abs() < 1e-9,
                  onTap: () => onChanged(_clamp(p)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openKeypad(BuildContext context) async {
    final controller =
        TextEditingController(text: value.toStringAsFixed(spec.decimals));
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(Tokens.radiusSheet),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  suffixText: spec.unit.trim(),
                  hintText: '${spec.min} – ${spec.max}',
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(
                  double.tryParse(v) ?? value,
                ),
              ),
              const SizedBox(height: Tokens.gapM),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(
                  double.tryParse(controller.text) ?? value,
                ),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) onChanged(_clamp(result));
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: AppColors.ink, size: 24),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Tokens.motionFast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.divider,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: Tokens.fontSmall,
            color: selected ? AppColors.accent : AppColors.inkSoft,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 时间点选择：小时 + 分钟两行步进，显示成 HH:mm。
/// 比原生滚轮更容易单手操作，也不会误触。
class TimeStepPicker extends StatelessWidget {
  const TimeStepPicker({
    super.key,
    required this.minutesOfDay,
    required this.onChanged,
  });

  final int minutesOfDay;
  final ValueChanged<String> onChanged;

  String get _label =>
      '${(minutesOfDay ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutesOfDay % 60).toString().padLeft(2, '0')}';

  void _bump(int deltaMinutes) {
    final next = (minutesOfDay + deltaMinutes + 1440) % 1440;
    final hh = (next ~/ 60).toString().padLeft(2, '0');
    final mm = (next % 60).toString().padLeft(2, '0');
    onChanged('$hh:$mm');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _label,
          style: const TextStyle(
            fontSize: Tokens.fontHeroLarge,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: Tokens.gapL),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: () => _bump(-60),
            ),
            const SizedBox(width: Tokens.gapXl),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: () => _bump(60),
            ),
            const SizedBox(width: Tokens.gapXxl),
            _StepButton(
              icon: Icons.keyboard_arrow_left_rounded,
              onTap: () => _bump(-5),
            ),
            const SizedBox(width: Tokens.gapXl),
            _StepButton(
              icon: Icons.keyboard_arrow_right_rounded,
              onTap: () => _bump(5),
            ),
          ],
        ),
        const SizedBox(height: Tokens.gapS),
        const Text(
          '左边整点，右边 5 分钟',
          style: TextStyle(fontSize: Tokens.fontCaption, color: AppColors.inkFaint),
        ),
      ],
    );
  }
}
