import 'package:exp_ledger/app.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动顺序：开库 → 补算遗留脏日 → 注入供应商 → 起界面。
///
/// 重算放在首帧之前，是为了避免"首页先显示旧数字，两秒后跳变"。
/// 失败不拦启动：让首页自己把错误显示出来，比白屏好。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppDatabase database = await AppDatabase.open();

  try {
    await SettlementRepository(database: database).recomputePending();
  } catch (error) {
    debugPrint('启动重算失败：$error');
  }

  // 系统重启后 alarm 会丢，这里每次启动重排一次（用户没开就什么都不做）。
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

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const ExpLedgerApp(),
    ),
  );
}
