/// 桌面小组件的桥。
///
/// 小组件只负责显示，不负责算：三个数字都在 Dart 侧算好再推过去。
/// 在 Kotlin 里重新实现一遍算法必然漂移——那是两个实现、两个真相。
///
/// 没有 Android 平台时（测试、桌面）静默返回 false，不抛异常。
library;

import 'package:flutter/services.dart';

class WidgetBridge {
  static const MethodChannel _channel = MethodChannel('exp_ledger/widget');

  /// 推三个字符串：今日净 EXP、等级、待确认数。
  Future<bool> push({
    required String exp,
    required String level,
    required String pending,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'push',
        <String, Object?>{'exp': exp, 'level': level, 'pending': pending},
      );
      return ok ?? false;
    } on MissingPluginException {
      // 非 Android 平台：没有这个通道，属正常情况。
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 清空小组件缓存（清空数据时用）。
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<bool>('clear');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
