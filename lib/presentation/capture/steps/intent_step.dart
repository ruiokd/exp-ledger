import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/capture/intent_matcher.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/widgets/option_tile.dart';
import 'package:flutter/material.dart';

/// S1：只说人话。
class IntentStep extends StatefulWidget {
  const IntentStep({
    super.key,
    required this.controller,
    required this.onVoice,
  });

  final CaptureController controller;
  final VoidCallback onVoice;

  @override
  State<IntentStep> createState() => _IntentStepState();
}

class _IntentStepState extends State<IntentStep> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _text = TextEditingController(
      text: s is CaptureIntentInput ? s.text : '',
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    if (v.isEmpty) return;
    widget.controller.dispatch(TextChanged(v));
    widget.controller.dispatch(const SubmitIntent());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: Tokens.gapS),
        const Text(
          '刚才发生了什么？',
          style: TextStyle(
            fontSize: Tokens.fontHeadline,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        const Text(
          '用你自己的话说就行，不用管格式。',
          style: TextStyle(fontSize: Tokens.fontBody, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Tokens.gapL),
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: _text,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: Tokens.fontBody),
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: false,
              hintText: '例如：今天做了一组深蹲',
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) => widget.controller.dispatch(TextChanged(v)),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: Tokens.gapM),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _submit,
                child: const Text('继续'),
              ),
            ),
            const SizedBox(width: Tokens.gapM),
            _RoundIcon(
              icon: Icons.mic_none_rounded,
              onTap: widget.onVoice,
            ),
          ],
        ),
        const SizedBox(height: Tokens.gapXl),
        const Text(
          '或者直接点一个',
          style: TextStyle(fontSize: Tokens.fontCaption, color: AppColors.inkFaint),
        ),
        const SizedBox(height: Tokens.gapS),
        Wrap(
          spacing: Tokens.gapS,
          runSpacing: Tokens.gapS,
          children: [
            for (final p in IntentMatcher.quickPhrases)
              GestureDetector(
                onTap: () {
                  _text.text = p;
                  widget.controller.dispatch(TextChanged(p));
                  widget.controller.dispatch(const SubmitIntent());
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Tokens.radiusChip),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Tokens.gapL),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

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
          width: 54,
          height: 54,
          child: Icon(icon, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}
