import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/data/models/data_models.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页：今天发生了什么，现在值多少，还差什么。
///
/// 三条产品约束，代码里必须体现：
///   1. 不给红色警报、不给"你退步了"这种判断；
///   2. 没有记录 ≠ 断签，只显示"今天还没有记录"；
///   3. 每个数字都能点进明细看到怎么算出来的（明细页）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TodayView> today = ref.watch(todayProvider);

    return RefreshIndicator(
      color: AppColors.calm,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(todayProvider);
        await ref.read(todayProvider.future);
      },
      child: today.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => ListView(
          padding: Tokens.pagePadding,
          children: <Widget>[
            SoftCard(
              child: Text(
                '读不出今天的数据：\n$error',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkSoft,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        data: (TodayView view) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: <Widget>[
            _SummaryCard(view: view),
            const SizedBox(height: Tokens.gapM),
            _AbilityCard(view: view),
            if (view.confirmations.isNotEmpty) ...<Widget>[
              const SizedBox(height: Tokens.gapM),
              _ConfirmCard(tasks: view.confirmations),
            ],
            if (view.pendingReviews > 0) ...<Widget>[
              const SizedBox(height: Tokens.gapM),
              SoftCard(
                color: AppColors.calmSoft,
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.autorenew_rounded,
                      size: 18,
                      color: AppColors.calm,
                    ),
                    const SizedBox(width: Tokens.gapS),
                    Expanded(
                      child: Text(
                        '还有 ${view.pendingReviews} 个词到期待复习。'
                        '复习会更新记忆强度，不复习就按遗忘曲线回落——不会扣分。',
                        style: const TextStyle(
                          fontSize: Tokens.fontSmall,
                          color: AppColors.inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Tokens.gapM),
            _EntriesCard(entries: view.entries, dayLabel: view.day.shortLabel),
            if (view.settlement?.alert != null) ...<Widget>[
              const SizedBox(height: Tokens.gapM),
              _AlertCard(view: view),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final paused = view.status == SettlementStatus.paused;
    final net = view.netExp;
    final sign = net > 0 ? '+' : '';

    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${view.day.month} 月 ${view.day.day} 日 · 周${view.day.weekdayLabel}',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                ),
              ),
              const Spacer(),
              _StatusChip(status: view.status),
            ],
          ),
          const SizedBox(height: Tokens.gapS),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                paused ? '0' : '$sign${net.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: Tokens.fontHero,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: paused
                      ? AppColors.inkFaint
                      : (net < 0 ? AppColors.negative : AppColors.ink),
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'EXP',
                  style: TextStyle(
                    fontSize: Tokens.fontSmall,
                    color: AppColors.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            paused
                ? '今天暂停结算：先照顾身体，账本明天再算。'
                : (view.hasRecord
                    ? '正向 ${view.settlement?.positiveExp.toStringAsFixed(1) ?? '0.0'}'
                        ' · 负向 ${view.settlement?.negativeExp.toStringAsFixed(1) ?? '0.0'}'
                    : '今天还没有记录。记一条，曲线才会动。'),
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: Tokens.gapL),
          Row(
            children: <Widget>[
              Text(
                '等级 ${view.snapshot?.level ?? 0}',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '距下一级 ${((1 - view.levelProgress) * 100).round()}%',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: view.levelProgress,
              minHeight: 7,
              backgroundColor: AppColors.surfaceMuted,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          Text(
            '缓冲池 ${(view.snapshot?.buffer ?? 0).toStringAsFixed(1)}'
            ' · 负向先扣缓冲，扣完才掉等级',
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SettlementStatus status;

  @override
  Widget build(BuildContext context) {
    final paused = status == SettlementStatus.paused;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: paused ? AppColors.calmSoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
      ),
      child: Text(
        paused ? '暂停结算' : status.label,
        style: TextStyle(
          fontSize: Tokens.fontCaption,
          fontWeight: FontWeight.w600,
          color: paused ? AppColors.calm : AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _AbilityCard extends StatelessWidget {
  const _AbilityCard({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '五维',
            style: TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '这是长期趋势值，不是今天的分数。完整度低 = 数据少，不 = 能力差。',
            style: TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          for (final ProjectAxis axis in ProjectAxis.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AxisRow(
                label: axis.label,
                value: view.abilityOf(axis),
                completeness: view.completenessOf(axis),
              ),
            ),
        ],
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.label,
    required this.value,
    required this.completeness,
  });

  final String label;
  final double value;
  final double completeness;

  @override
  Widget build(BuildContext context) {
    // 完整度直接映射成透明度：数据越少，颜色越淡，而不是数字越小。
    final opacity = 0.35 + 0.65 * completeness.clamp(0.0, 1.0);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value / 120).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceMuted,
              color: AppColors.calm.withOpacity(opacity),
            ),
          ),
        ),
        const SizedBox(width: Tokens.gapS),
        SizedBox(
          width: 52,
          child: Text(
            '${value.toStringAsFixed(0)} · ${(completeness * 100).round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmCard extends ConsumerWidget {
  const _ConfirmCard({required this.tasks});

  final List<ConfirmationTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: AppColors.calm,
              ),
              const SizedBox(width: Tokens.gapS),
              Text(
                '要确认 ${tasks.length} 件事',
                style: const TextStyle(
                  fontSize: Tokens.fontBody,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.gapS),
          for (final ConfirmationTask t in tasks) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.title,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (t.detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        t.detail,
                        style: const TextStyle(
                          fontSize: Tokens.fontCaption,
                          color: AppColors.inkFaint,
                          height: 1.45,
                        ),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(confirmationRepositoryProvider)
                              .markDone(t.id);
                          ref.invalidate(todayProvider);
                        },
                        child: const Text('记下了'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(confirmationRepositoryProvider)
                              .skip(t.id);
                          ref.invalidate(todayProvider);
                        },
                        child: const Text('先跳过'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
          ],
        ],
      ),
    );
  }
}

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({required this.entries, required this.dayLabel});

  final List<DraftEntry> entries;
  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '$dayLabel 的记录',
                style: const TextStyle(
                  fontSize: Tokens.fontBody,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length} 条',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Tokens.gapS),
              child: Text(
                '空白也是一种数据：它会进曲线，只是不加分。',
                style: TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkFaint,
                  height: 1.5,
                ),
              ),
            ),
          for (final DraftEntry e in entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.valence == Valence.negative
                          ? AppColors.negative
                          : AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: Tokens.gapS),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          e.interpretation,
                          style: const TextStyle(
                            fontSize: Tokens.fontSmall,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.axis.label} · ${e.planStatus.label} · '
                          '${e.confidence.badgeLabel}'
                          '${e.revision > 0 ? ' · 修订 ${e.revision}' : ''}',
                          style: const TextStyle(
                            fontSize: Tokens.fontCaption,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context) {
    final alert = view.settlement!.alert!;
    return SoftCard(
      color: AppColors.calmSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            alert.title,
            style: const TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.calm,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${alert.message} ${alert.advice}',
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
