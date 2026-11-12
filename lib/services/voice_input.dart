import 'package:flutter/services.dart';

/// 离线语音输入。
///
/// 硬约束：本 App 不申请 INTERNET 权限。因此这里只接受
/// 系统识别器的**离线**结果；设备不支持离线识别时返回 null，
/// UI 会隐藏语音入口并提示用键盘，不阻塞任何主流程。
class VoiceInput {
  const VoiceInput();

  static const MethodChannel _channel = MethodChannel('exp_ledger/voice');

  /// 返回识别到的文本；不可用时返回 null（不是抛异常）。
  Future<String?> listen() async {
    try {
      final result = await _channel.invokeMethod<String>('listen');
      final text = result?.trim();
      return (text == null || text.isEmpty) ? null : text;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 设备是否支持离线识别。UI 用它决定要不要显示麦克风。
  Future<bool> get available async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
