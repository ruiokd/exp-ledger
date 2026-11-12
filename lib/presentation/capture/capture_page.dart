import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/steps/intent_step.dart';
import 'package:exp_ledger/presentation/capture/steps/question_step.dart';
import 'package:exp_ledger/presentation/capture/steps/receipt_step.dart';
import 'package:exp_ledger/presentation/capture/steps/simple_steps.dart';
import 'package:exp_ledger/services/voice_input.dart';
import 'package:flutter/material.dart';

/// 采集窗口。首页第一入口，通话式而非表单式。
///
/// 结构：悬浮卡片 + 顶部一句上下文 + 可切换内容区。
/// 所有状态来自 [CaptureController]，这个文件里没有任何业务判断。
class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.controller,
    this.onCommitted,
  });

  final CaptureController controller;
  final void Function(DraftEntry entry)? onCommitted;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final GlobalKey<ScaffoldState> _key = GlobalKey<ScaffoldState>();
  final VoiceInput voice = const VoiceInput();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final s = widget.controller.state;
    if (s is CaptureCommitted) {
      widget.onCommitted?.call(s.entry);
    }
  }

  Future<void> _startVoice() async {
    final result = await voice.listen();
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这台设备没有离线语音识别，用键盘说也一样，我等着'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    widget.controller.dispatch(VoiceResult(result));
  }

  String get _contextTitle {
    final s = widget.controller.state;
    if (s is CaptureQuestioning) return s.behavior.name;
    if (s is CapturePlanGate) return s.behavior.name;
    if (s is CaptureReceipting) return s.behavior.name;
    if (s is CaptureDisambiguating) return '确认一下';
    if (s is CaptureFreeform) return '自由记录';
    return '记录点什么';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      key: _key,
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: _contextTitle,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(Tokens.radiusSheet),
                      ),
                      boxShadow: SoftShadow.sheet,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(Tokens.radiusSheet),
                      ),
                      child: AnimatedSwitcher(
                        duration: Tokens.motionBase,
                        switchInCurve: Tokens.motionCurve,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: SingleChildScrollView(
                          key: ValueKey(_stageKey(state)),
                          padding: EdgeInsets.fromLTRB(
                            Tokens.gapXl,
                            Tokens.gapXl,
                            Tokens.gapXl,
                            Tokens.gapXl + bottomInset,
                          ),
                          child: _body(state),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stageKey(CaptureState s) {
    if (s is CaptureIdle) return 'idle';
    if (s is CaptureIntentInput) return 'intent';
    if (s is CaptureDisambiguating) return 'disambig-${s.candidates.length}';
    if (s is CapturePlanGate) return 'plan-${s.behavior.code}';
    if (s is CaptureQuestioning) return 'q-${s.behavior.code}-${s.answeredIds.length}';
    if (s is CaptureReceipting) return 'receipt-${s.behavior.code}';
    if (s is CaptureCommitted) return 'done';
    if (s is CaptureFreeform) return 'freeform';
    return 'aborted';
  }

  Widget _body(CaptureState state) {
    if (state is CaptureIntentInput || state is CaptureIdle) {
      return IntentStep(
        controller: widget.controller,
        onVoice: _startVoice,
      );
    }
    if (state is CaptureDisambiguating) {
      return DisambiguateStep(controller: widget.controller, state: state);
    }
    if (state is CapturePlanGate) {
      return PlanGateStep(controller: widget.controller, state: state);
    }
    if (state is CaptureQuestioning) {
      return QuestionStep(controller: widget.controller, state: state);
    }
    if (state is CaptureReceipting) {
      return ReceiptStep(controller: widget.controller, state: state);
    }
    if (state is CaptureFreeform) {
      return FreeformStep(controller: widget.controller, state: state);
    }
    if (state is CaptureCommitted) {
      return const _DonePlaceholder();
    }
    return _ClosedStep(onRestart: widget.controller.restart);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: AppColors.inkSoft),
            tooltip: '关闭',
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onClose,
            child: const Text('稍后再说'),
          ),
        ],
      ),
    );
  }
}

class _DonePlaceholder extends StatelessWidget {
  const _DonePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          '记下了',
          style: TextStyle(
            fontSize: Tokens.fontTitle,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _ClosedStep extends StatelessWidget {
  const _ClosedStep({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        const Text(
          '这次的记录没有存下来',
          style: TextStyle(fontSize: Tokens.fontTitle, color: AppColors.ink),
        ),
        const SizedBox(height: Tokens.gapS),
        const Text(
          '没关系的，想起来再说。',
          style: TextStyle(fontSize: Tokens.fontSmall, color: AppColors.inkSoft),
        ),
        const SizedBox(height: Tokens.gapXl),
        FilledButton(
          onPressed: onRestart,
          child: const Text('再来一次'),
        ),
      ],
    );
  }
}
