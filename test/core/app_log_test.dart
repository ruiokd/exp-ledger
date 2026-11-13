import 'package:exp_ledger/core/log/app_log.dart';
import 'package:test/test.dart';

/// 日志器是纯 Dart（零 Flutter 依赖），所以用 package:test 直接跑。
void main() {
  setUp(() => appLog.clear());

  test('环形缓冲不会超过容量', () {
    for (int i = 0; i < AppLog.capacity + 50; i++) {
      logInfo('t', 'line $i');
    }
    expect(appLog.length, AppLog.capacity);
    // 最旧的被丢掉了，最新的还在。
    final List<LogEntry> all = appLog.snapshot();
    expect(all.first.message, 'line 50');
    expect(all.last.message, 'line ${AppLog.capacity + 49}');
  });

  test('按级别筛选：只留警告以上', () {
    logDebug('t', 'd');
    logInfo('t', 'i');
    logWarn('t', 'w');
    logError('t', 'e');
    final List<LogEntry> warnUp = appLog.snapshot(minLevel: LogLevel.warn);
    expect(warnUp.map((LogEntry e) => e.message), <String>['w', 'e']);
    expect(appLog.snapshot(minLevel: LogLevel.error).length, 1);
    expect(appLog.snapshot(minLevel: null).length, 4);
  });

  test('errorCount 只数 error', () {
    logError('t', 'e1');
    logError('t', 'e2');
    logWarn('t', 'w');
    expect(appLog.errorCount, 2);
  });

  test('detail 会被截断，避免日志被一行堆栈撑爆', () {
    logError('t', 'boom', detail: 'x' * (AppLog.maxDetailLength + 500));
    final LogEntry e = appLog.snapshot().single;
    expect(e.detail.length, AppLog.maxDetailLength + 1); // 尾部一个省略号
    expect(e.detail.endsWith('…'), isTrue);
  });

  test('logError 把异常与堆栈拼进 detail', () {
    logError(
      't',
      '失败',
      error: StateError('炸了'),
      stack: StackTrace.current,
    );
    final LogEntry e = appLog.snapshot().single;
    expect(e.detail, contains('StateError'));
    expect(e.detail, contains('炸了'));
    expect(e.detail, contains('app_log_test.dart'));
  });

  test('dump 带表头时能直接发给别人', () {
    logInfo('db', '打开成功');
    final String text = appLog.dump(header: '标题行');
    expect(text, startsWith('标题行'));
    expect(text, contains('[db] 打开成功'));
    expect(text, contains(' I [db] '));
  });

  test('seedFromLines 把上次运行的日志塞回来（标 last）', () {
    appLog.seedFromLines(<String>['旧日志一', '旧日志二', '']);
    final List<LogEntry> all = appLog.snapshot();
    expect(all.length, 2); // 空行被跳过
    expect(all.first.tag, 'last');
    expect(all.first.message, '旧日志一');
  });

  test('落盘钩子抛异常不影响调用方', () {
    appLog.attachSink((LogEntry e) => throw StateError('盘满了'));
    expect(() => logInfo('t', '依然写得进去'), returnsNormally);
    expect(appLog.length, 1);
    appLog.attachSink(null);
  });

  test('清空后条数归零', () {
    logInfo('t', 'a');
    appLog.clear();
    expect(appLog.length, 0);
    expect(appLog.errorCount, 0);
  });
}
