import 'dart:async';

import 'package:exp_ledger/app.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/presentation/startup/startup_failure_app.dart';
import 'package:exp_ledger/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动顺序：开库（带超时）→ 补算遗留脏日 → 注入供应商 → 起界面。
///
/// 两条硬教训（v1.0.0 黑屏换来的）：
///   1. **`runApp` 之前不能有无保护的 await**。v1 里 `AppDatabase.open()`
///      直接裸奔，它一抛异常，`runApp` 永远不会执行，屏幕上就是纯黑——
///      而且因为没有 native crash，系统连"应用已停止"都不弹。
///   2. **超时必须有**。挂起和抛异常在用户眼里都是黑屏，但处理方式不同：
///      抛异常能显示原因，挂起只能等。8 秒拿不到库就当失败。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // build 期间抛异常时，release 默认显示一块灰；换成能读、能复制的东西。
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      StartupErrorView.fromFlutterError(details);

  // 让失败页上的"再试一次"能重跑同一套启动流程。
  bootApp = _boot;
  restartApp = _launch;

  final BootResult result = await _boot();
  if (!result.ok) {
    runApp(StartupFailureApp(result: result));
    return;
  }
  _launchWith(result.database!);
}

Future<void> _launch() async {
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
}

Future<BootResult> _boot() async {
  AppDatabase database;
  try {
    database = await AppDatabase.open().timeout(const Duration(seconds: 8));
  } on TimeoutException catch (error, stack) {
    return BootResult(
      stage: '打开数据库（8 秒没返回，疑似插件通道挂住）',
      error: error,
      stack: stack,
    );
  } catch (error, stack) {
    return BootResult(stage: '打开数据库', error: error, stack: stack);
  }

  // 下面两步失败不该拦住启动：账本能用比什么都重要。
  try {
    await SettlementRepository(database: database).recomputePending();
  } catch (error) {
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
    }
  } catch (error) {
    debugPrint('恢复提醒失败：$error');
  }

  return BootResult(database: database, stage: 'ok');
}
