import 'package:exp_ledger/domain/capture/capture_state.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:flutter/foundation.dart';

/// 采集窗口的控制器：把纯状态机包成 UI 能监听的对象。
///
/// 它只做三件事：转发事件、暴露状态、在落库时回调一次。
/// 任何业务判断都不在这里——这样第 3/4 步改引擎时不用动 UI。
class CaptureController extends ChangeNotifier {
  CaptureController({
    required this.machine,
    this.onCommit,
    this.onAbort,
  });

  final CaptureMachine machine;
  final void Function(DraftEntry entry)? onCommit;
  final VoidCallback? onAbort;

  CaptureState _state = const CaptureIdle();

  CaptureState get state => _state;

  UserProfile get profile => machine.deps.profile();

  Map<String, Object?>? lastAnswersFor(String code) =>
      machine.deps.lastAnswers?.call(code);

  void dispatch(CaptureEvent event) {
    final next = machine.reduce(_state, event);
    if (identical(next, _state)) return;
    _state = next;
    notifyListeners();
    if (next is CaptureCommitted) {
      onCommit?.call(next.entry);
    }
    if (next is CaptureAborted) {
      onAbort?.call();
    }
  }

  /// 从首页快捷方式直接进入某个行为（跳过意图识别）。
  void startWithBehavior(String code) => dispatch(PickByCode(code));

  /// 从快捷短语进入（等于"说了一句话"）。
  void startWithPhrase(String phrase) {
    dispatch(TextChanged(phrase));
    dispatch(const SubmitIntent());
  }

  void restart() {
    _state = const CaptureIdle();
    notifyListeners();
  }

  /// 供 UI 判断"这一屏要不要自动聚焦键盘"——只有数字题才需要，
  /// 而且默认不聚焦（按钮优先）。
  bool get prefersKeyboard => false;
}
