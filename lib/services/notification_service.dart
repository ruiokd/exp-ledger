/// 本地提醒。
///
/// 只有一条：每天固定时间问一句"今天记了吗"。
///
/// 三条产品红线（写在这里，改代码时别越过去）：
///   1. **没有连续天数**。断签威胁是把记录变成作业；
///   2. **没有"你已 3 天没记录"**。App 不统计缺席，只提供入口；
///   3. 通知文案里不出现任何数字评价。
///
/// 时区处理：用"本地时间算出的绝对时刻 + UTC location"调度，
/// 不依赖 timezone 包的本地 location 解析（那需要额外的时区插件）。
/// 代价是 DST 地区在切换后偏一小时——每次启动都会重新调度，影响最多一天。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int dailyNudgeId = 1001;
  static const String channelId = 'daily_nudge';
  static const String channelName = '每日一问';

  static const String defaultTitle = '一分钟，记一下今天';
  static const String defaultBody = '记完就关掉。没记也不会扣分——明天还是同一天。';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('ic_notification');
    const InitializationSettings settings =
        InitializationSettings(android: android);
    await _plugin.initialize(settings);
    _ready = true;
  }

  /// 请求通知权限（Android 13+ 需要）。
  /// 用户拒绝就返回 false——App 不追问，也不影响任何记录功能。
  Future<bool> requestPermission() async {
    await init();
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final bool? granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 排一条每日提醒。重复调度会先取消旧的，避免一天响两次。
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String title = defaultTitle,
    String body = defaultBody,
  }) async {
    await init();
    await cancelDaily();

    final DateTime now = DateTime.now();
    DateTime next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    // 绝对时刻调度：UTC location 不参与 DST 计算，因此时间点稳定。
    final tz.TZDateTime when = tz.TZDateTime.from(next.toUtc(), tz.UTC);

    await _plugin.zonedSchedule(
      dailyNudgeId,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '每天一次，问一句今天记了吗。没有连续天数，也不催。',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // iOS 侧需要这个参数（Android 不用），但签名里是 required。
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDaily() async {
    await init();
    await _plugin.cancel(dailyNudgeId);
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// 当前是否真的有排程（用户可能在系统设置里关掉了通知）。
  Future<bool> hasPendingReminder() async {
    await init();
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    return pending.any((PendingNotificationRequest p) => p.id == dailyNudgeId);
  }
}
