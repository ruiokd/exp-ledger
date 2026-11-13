import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/db/schema.dart';
import 'package:exp_ledger/data/repository/setting_repository.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/presentation/anchor/anchor_page.dart';
import 'package:exp_ledger/presentation/settings/log_page.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置：档案、数据概况、系数覆盖、维护操作。
///
/// 这一页只做两件"危险"事：导出与清空。两个都要点两次，
/// 而且清空要把"删什么、不删什么"写在按钮上方。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SettingsView> async = ref.watch(settingsProvider);

    return RefreshIndicator(
      color: AppColors.calm,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(settingsProvider);
        await ref.read(settingsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: <Widget>[
          async.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stack) => SoftCard(
              child: Text(
                '读不出设置：$error',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            data: (SettingsView view) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ProfileCard(view: view),
                const SizedBox(height: Tokens.gapM),
                const _AnchorEntryCard(),
                const SizedBox(height: Tokens.gapM),
                const _LogEntryCard(),
                const SizedBox(height: Tokens.gapM),
                const _ReminderCard(),
                const SizedBox(height: Tokens.gapM),
                _DataCard(view: view),
                const SizedBox(height: Tokens.gapM),
                _ConfigCard(view: view),
                const SizedBox(height: Tokens.gapM),
                _ActionsCard(),
                const SizedBox(height: Tokens.gapM),
                const _AboutCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.view});

  final SettingsView view;

  @override
  Widget build(BuildContext context) {
    final p = view.profile;
    final rows = <(String, String)>[
      ('身高 / 体重', '${p.heightCm.toStringAsFixed(0)} cm · ${p.weightKg.toStringAsFixed(1)} kg'),
      ('年龄 / 性别', '${p.age} · ${p.sex.label}'),
      ('静息心率', '${p.restingHeartRate} 次/分'),
      ('睡眠需求', '${p.sleepNeedHours.toStringAsFixed(1)} 小时'),
      ('熬夜界线', '${p.sleepLine.label} 之后算熬夜'),
      ('词汇量估计', '${p.vocabularyEstimate}'),
      if (p.oneRmSquatKg != null) ('深蹲 1RM', '${p.oneRmSquatKg!.toStringAsFixed(1)} kg'),
      if (p.vo2MaxEstimate != null)
        ('VO2max', '${p.vo2MaxEstimate!.toStringAsFixed(1)} ml/kg/min'),
      if (p.bodyFatPercent != null)
        ('体脂', '${p.bodyFatPercent!.toStringAsFixed(1)}%'),
    ];

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '基线档案',
                style: TextStyle(
                  fontSize: Tokens.fontBody,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              _ConfidenceTag(confidence: p.overallConfidence),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '所有公式的个体化参数都从这里读。改档案不会改历史结算，'
            '要让曲线重算，用下面的"重算最近 90 天"。',
            style: TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          for (final (String label, String value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfidenceTag extends StatelessWidget {
  const _ConfidenceTag({required this.confidence});

  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    final Color color = confidence == Confidence.calibrated
        ? AppColors.confidenceCalibrated
        : (confidence == Confidence.formula
            ? AppColors.confidenceFormula
            : AppColors.confidenceSelfReport);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
      ),
      child: Text(
        confidence.receiptLabel,
        style: TextStyle(
          fontSize: Tokens.fontCaption,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.view});

  final SettingsView view;

  static const List<(String, String)> _interesting = <(String, String)>[
    (Tables.dailyLog, '原始记录'),
    (Tables.dailyLogHistory, '修订历史'),
    (Tables.daySettlement, '每日结算'),
    (Tables.valenceEvent, '正向事件'),
    (Tables.negativeEvent, '负向事件'),
    (Tables.abilitySnapshot, '能力快照'),
    (Tables.forecastPoint, '预测点'),
  ];

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '数据概况',
            style: TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '全部本地 · 无网络权限 · 无账号。'
            '${view.dirtyCount > 0 ? '有 ${view.dirtyCount} 天待重算。' : '脏日队列已清空。'}',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          for (final (String table, String label) in _interesting)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${view.rowCounts[table] ?? 0}',
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            '记忆条目 ${view.memoryCount}',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({required this.view});

  final SettingsView view;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, ({double current, double baseline})>> changed =
        view.configDiff.entries
            .where((MapEntry<String, ({double current, double baseline})> e) =>
                (e.value.current - e.value.baseline).abs() > 1e-9)
            .toList();

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '系数',
            style: TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            changed.isEmpty
                ? '全部使用默认值。改系数会触发整条曲线重算——'
                    '这正是"可解释"的代价与好处。'
                : '${changed.length} 项被改过（默认值 → 当前值）。',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
          if (changed.isNotEmpty) ...[
            const SizedBox(height: Tokens.gapM),
            for (final MapEntry<String, ({double current, double baseline})> e
                in changed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: Tokens.fontSmall,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                    Text(
                      '${e.value.baseline.toStringAsFixed(3)} → '
                      '${e.value.current.toStringAsFixed(3)}',
                      style: const TextStyle(
                        fontSize: Tokens.fontSmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.calm,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionsCard extends ConsumerWidget {
  const _ActionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '维护',
            style: TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          _ActionRow(
            icon: Icons.ios_share_rounded,
            title: '导出全部数据',
            subtitle: '生成一份 JSON（含所有表），调起系统分享面板',
            onTap: () async {
              try {
                final bool ok =
                    await ref.read(exportServiceProvider).share();
                if (!context.mounted) return;
                if (!ok) {
                  await _copyToClipboard(context, ref);
                }
              } catch (error) {
                if (!context.mounted) return;
                await _copyToClipboard(context, ref, error: error);
              }
            },
          ),
          const Divider(height: 20, color: AppColors.divider),
          _ActionRow(
            icon: Icons.refresh_rounded,
            title: '重算最近 90 天',
            subtitle: '从 90 天前重跑到今天。改过系数或档案后用它',
            onTap: () async {
              final DayKey from = DayKey.today().addDays(-89);
              final run = await ref
                  .read(settlementRepositoryProvider)
                  .recomputeFrom(from);
              ref.invalidate(todayProvider);
              ref.invalidate(settingsProvider);
              ref.invalidate(recentDaysProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已重算 ${run.count} 天')),
              );
            },
          ),
          const Divider(height: 20, color: AppColors.divider),
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            title: '清空所有数据',
            subtitle: '删除全部记录、结算、快照、预测与系数覆盖。不可撤销',
            danger: true,
            onTap: () async {
              final bool? sure = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  ),
                  title: const Text('清空所有数据？'),
                  content: const Text(
                    '会删掉：原始记录、修订历史、每日结算、五维快照、预测点、'
                    '记忆条目、确认任务、徽章、系数覆盖。\n\n'
                    '不会删掉：基线档案（身高体重那些）。\n\n'
                    '这个动作没有撤销。',
                    style: TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkSoft,
                      height: 1.6,
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('再想想'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text(
                        '确认清空',
                        style: TextStyle(color: AppColors.negative),
                      ),
                    ),
                  ],
                ),
              );
              if (sure != true) return;
              await ref.read(maintenanceRepositoryProvider).wipeAll();
              ref.invalidate(todayProvider);
              ref.invalidate(settingsProvider);
              ref.invalidate(recentDaysProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清空')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 分享面板打不开时的兜底：至少让人能把 JSON 拿走。
Future<void> _copyToClipboard(
  BuildContext context,
  WidgetRef ref, {
  Object? error,
}) async {
  final String json =
      await ref.read(maintenanceRepositoryProvider).exportJson(pretty: true);
  await Clipboard.setData(ClipboardData(text: json));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error == null
            ? '分享面板不可用，已复制 ${json.length} 个字符到剪贴板'
            : '分享失败（$error），已复制到剪贴板',
      ),
    ),
  );
}

/// 提醒设置。
///
/// 默认关闭，时间默认 21:30。打开时才请求系统权限——
/// 一上来就弹权限框的 App，用户第一反应是拒绝。
class _ReminderCard extends ConsumerWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ReminderSettings> async = ref.watch(reminderProvider);

    return SoftCard(
      child: async.when(
        loading: () => const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (Object error, StackTrace stack) => Text(
          '读不出提醒设置：$error',
          style: const TextStyle(
            fontSize: Tokens.fontSmall,
            color: AppColors.inkSoft,
          ),
        ),
        data: (ReminderSettings r) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '每日一问',
                    style: TextStyle(
                      fontSize: Tokens.fontBody,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Switch(
                  value: r.enabled,
                  activeColor: Colors.white,
                  activeTrackColor: AppColors.calm,
                  onChanged: (bool v) => _toggle(context, ref, r, v),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '每天一个固定时间，问一句"今天记了吗"。没有连续天数、'
              '不统计缺席、不催。关掉就真的不再响。',
              style: TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
                height: 1.45,
              ),
            ),
            const SizedBox(height: Tokens.gapS),
            InkWell(
              borderRadius: BorderRadius.circular(Tokens.radiusSmall),
              onTap: r.enabled
                  ? () => _pickTime(context, ref, r)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      '提醒时间',
                      style: TextStyle(
                        fontSize: Tokens.fontSmall,
                        color: r.enabled
                            ? AppColors.inkSoft
                            : AppColors.inkFaint,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      r.label,
                      style: TextStyle(
                        fontSize: Tokens.fontSmall,
                        fontWeight: FontWeight.w700,
                        color: r.enabled
                            ? AppColors.ink
                            : AppColors.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: r.enabled
                          ? AppColors.inkFaint
                          : AppColors.inkFaint.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    ReminderSettings r,
    bool enabled,
  ) async {
    final SettingRepository settings = ref.read(settingRepositoryProvider);
    final NotificationService notifier = ref.read(notificationServiceProvider);

    if (enabled) {
      final bool granted = await notifier.requestPermission();
      await settings.writeBool(SettingRepository.reminderEnabled, true);
      await notifier.scheduleDaily(hour: r.hour, minute: r.minute);
      if (!context.mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('系统没给通知权限：到系统设置里打开后，这里再关一次再开'),
          ),
        );
      }
    } else {
      await settings.writeBool(SettingRepository.reminderEnabled, false);
      await notifier.cancelDaily();
    }
    ref.invalidate(reminderProvider);
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    ReminderSettings r,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.hour, minute: r.minute),
      helpText: '选一个每天都会响的时间',
    );
    if (picked == null) return;

    final SettingRepository settings = ref.read(settingRepositoryProvider);
    await settings.writeInt(SettingRepository.reminderHour, picked.hour);
    await settings.writeInt(SettingRepository.reminderMinute, picked.minute);

    if (r.enabled) {
      await ref.read(notificationServiceProvider).scheduleDaily(
            hour: picked.hour,
            minute: picked.minute,
          );
    }
    ref.invalidate(reminderProvider);
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppColors.negative : AppColors.inkSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusSmall),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Tokens.gapM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: Tokens.fontSmall,
                      fontWeight: FontWeight.w600,
                      color: danger ? AppColors.negative : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkFaint,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.surfaceMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '关于',
            style: TextStyle(
              fontSize: Tokens.fontSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '经验账本 · 本地版\n'
            'ACWR / sRPE 源自竞技体育研究，用于普通人群属外推近似，'
            '只作趋势提示，不预测伤病、不构成诊断。\n'
            '涉及胸痛、晕厥、酱油色尿等信号时，App 会暂停当日结算并建议就医——'
            '它不判断病情，也不替代医生。',
            style: TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 刻度标定入口。放在档案卡下面：它不是「设置项」，
/// 是「你的事怎么量」这件事本身的入口。
class _AnchorEntryCard extends StatelessWidget {
  const _AnchorEntryCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AnchorPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '刻度标定',
                      style: TextStyle(
                        fontSize: Tokens.fontBody,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '给说不清怎么量的行为定单位与量级（先验，权重 ≤50%）',
                      style: TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// 运行日志入口。放在刻度标定下面：它不是设置项，是"出问题时的出口"。
class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LogPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '运行日志',
                      style: TextStyle(
                        fontSize: Tokens.fontBody,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '出异常时复制整段发过来（不含行为内容与数值）',
                      style: TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
