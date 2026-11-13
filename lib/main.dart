import 'dart:async';

import 'package:exp_ledger/app.dart';
import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/presentation/startup/startup_failure_app.dart';
import 'package:exp_ledger/services/log_service.dart';
import 'package:exp_ledger/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动顺序：日志 → 开库（带超时）→ 补算遗留脏日 → 注入供应商 → 起界面。
///
/// 三条硬教训（v1.0.0 黑屏换来的）：
///   1. **`runApp` 之前不能有无保护的 await**。v1 里 `AppDatabase.open()`
///      直接裸奔，它一抛异常，`runApp` 永远不会执行，屏幕上就是纯黑——
///      而且因为没有 native crash，系统连"应用已停止"都不弹。
///   2. **超时必须有**。挂起和抛异常在用户眼里都是黑屏，但处理方式不同：
///      抛异常能显示原因，挂起只能等。8 秒拿不到库就当失败。
///   3. **日志先于一切**。它自己失败也只是降级成内存日志，不许拦住启动
///      （见 `LogService.init` 里的 try/catch 与 sink 失败兜底）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先把日志立起来，后面每一步都能留下痕迹。init 内部全 try/catch。
  await LogService.init();
  LogService.installHandlers();
  logInfo('boot', '应用启动');

  // build 期间抛异常时，release 默认显示一块灰；换成能读、能复制的东西。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      StartupErrorView.fromFlutterError(details);

  // 让失败页上的"再试一次"能重跑同一套启动流程。
  bootApp = _boot;
  restartApp = _launch;

  // 兜住 zone 里没人接的异步异常（Future 忘了 catch 的那类）。
  await runZonedGuarded<Future<void>>(
    () async {
      final BootResult result = await _boot();
      if (!result.ok) {
        runApp(StartupFailureApp(result: result));
        return;
      }
      _launchWith(result.database!);
    },
    (Object error, StackTrace stack) {
      logError('zone', '未捕获的异步异常', error: error, stack: stack);
    },
  );
}

Future<void> _launch() async {
  logInfo('boot', '重试启动');
  final BootResult result = await _boot();
  if (!result.ok) {
    runApp(StartupFailureApp(result: result));
    return;
  }
  _launchWith(result.database!);
}

void _launchWith(AppDatabase database) {
  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const ExpLedgerApp(),
    ),
  );
  logInfo('boot', '界面已提交渲染');
  // 首帧到达才算"能用了"——黑屏事故里，runApp 成功 ≠ 界面出现。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    logInfo('boot', '首帧已渲染');
  });
}

Future<BootResult> _boot() async {
  AppDatabase database;
  try {
    database = await AppDatabase.open().timeout(const Duration(seconds: 8));
    logInfo('db', '数据库打开成功', detail: 'schema v${Migrations.version}');
  } on TimeoutException catch (error, stack) {
    logError('db', '打开数据库超时（8 秒）', error: error, stack: stack);
    return BootResult(
      stage: '打开数据库（8 秒没返回，疑似插件通道挂住）',
      error: error,
      stack: stack,
    );
  } catch (error, stack) {
    logError('db', '打开数据库失败', error: error, stack: stack);
    return BootResult(stage: '打开数据库', error: error, stack: stack);
  }

  // 下面两步失败不该拦住启动：账本能用比什么都重要。
  try {
    await SettlementRepository(database: database).recomputePending();
    logInfo('settle', '启动补算完成');
  } catch (error, stack) {
    logError('settle', '启动补算失败（已跳过）', error: error, stack: stack);
    debugPrint('启动重算失败：$error');
  }

  try {
    final SettingRepository settings = SettingRepository(database: database);
    if (await settings.readBool(SettingRepository.reminderEnabled)) {
      await NotificationService().scheduleDaily(
        hour: await settings.readInt(
          SettingRepository.reminderHour,
          fallback: 21,
        ),
        minute: await settings.readInt(
          SettingRepository.reminderMinute,
          fallback: 30,
        ),
      );
      logInfo('notify', '提醒已重排');
    }
  } catch (error, stack) {
    logError('notify', '恢复提醒失败（已跳过）', error: error, stack: stack);
    debugPrint('恢复提醒失败：$error');
  }

  return BootResult(database: database, stage: 'ok');
}
