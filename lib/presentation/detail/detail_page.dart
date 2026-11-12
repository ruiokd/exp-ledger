import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/valence_event.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 明细：这一天的分是怎么来的。
///
/// 这是"可解释性"的落点——首页任何一个数字，都能在这里找到
/// 基础分、加成、权重、状态乘数、置信度折价，以及最后乘出来的 EXP。
class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  DayKey? _selected;

  DayKey get _day => _selected ?? DayKey.today();

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DayKey>> days = ref.watch(recentDaysProvider);
    final AsyncValue<DaySettlement?> detail = ref.watch(dayDetailProvider(_day));
    final AsyncValue<List<DraftEntry>> entries =
        ref.watch(dayEntriesProvider(_day));

    return RefreshIndicator(
      color: AppColors.calm,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(recentDaysProvider);
        ref.invalidate(dayDetailProvider(_day));
        ref.invalidate(dayEntriesProvider(_day));
        await ref.read(dayDetailProvider(_day).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
        children: <Widget>[
          days.maybeWhen(
            data: (List<DayKey> list) => _DayPicker(
              days: list,
              selected: _day,
              onSelect: (DayKey d) => setState(() => _selected = d),
            ),
            orElse: () => const SizedBox(height: 40),
          ),
          const SizedBox(height: Tokens.gapM),
          detail.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stack) => SoftCard(
              child: Text(
                '读不出这一天的结算：$error',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            data: (DaySettlement? s) => s == null
                ? const SoftCard(
                    child: Text(
                      '这一天还没有结算记录。\n空白日也会进曲线（状态继续衰减），'
                      '只是没有加减分。',
                      style: TextStyle(
                        fontSize: Tokens.fontSmall,
                        color: AppColors.inkFaint,
                        height: 1.6,
                      ),
                    ),
                  )
                : _SettlementDetail(settlement: s),
          ),
          const SizedBox(height: Tokens.gapM),
          entries.maybeWhen(
            data: (List<DraftEntry> list) => _RawEntries(entries: list),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<DayKey> days;
  final DayKey selected;
  final ValueChanged<DayKey> onSelect;

  @override
  Widget build(BuildContext context) {
    final DayKey today = DayKey.today();
    final List<DayKey> options = <DayKey>[
      today,
      ...days.where((DayKey d) => d != today),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final DayKey d in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(Tokens.radiusChip),
                onTap: () => onSelect(d),
                child: AnimatedContainer(
                  duration: Tokens.motionFast,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: d == selected ? AppColors.ink : AppColors.surface,
                    borderRadius: BorderRadius.circular(Tokens.radiusChip),
                  ),
                  child: Text(
                    d == today ? '今天' : '${d.month}/${d.day}',
                    style: TextStyle(
                      fontSize: Tokens.fontCaption,
                      fontWeight:
                          d == selected ? FontWeight.w600 : FontWeight.w500,
                      color: d == selected ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettlementDetail extends StatelessWidget {
  const _SettlementDetail({required this.settlement});

  final DaySettlement settlement;

  @override
  Widget build(BuildContext context) {
    final bool paused = settlement.status == SettlementStatus.paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${settlement.dayKey.month} 月 ${settlement.dayKey.day} 日',
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    settlement.status.label,
                    style: TextStyle(
                      fontSize: Tokens.fontCaption,
                      fontWeight: FontWeight.w600,
                      color:
                          paused ? AppColors.calm : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.gapS),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '${settlement.netExp >= 0 ? '+' : ''}${settlement.netExp.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: Tokens.fontMetric,
                      fontWeight: FontWeight.w700,
                      color: settlement.netExp < 0
                          ? AppColors.negative
                          : AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'EXP',
                      style: TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '正向 +${settlement.positiveExp.toStringAsFixed(1)} · '
                '负向 ${settlement.negativeExp.toStringAsFixed(1)} · '
                '等级 ${settlement.levelBefore} → ${settlement.levelAfter} · '
                '缓冲 ${settlement.bufferAfter.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                  height: 1.5,
                ),
              ),
              if (settlement.isInterruption)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '中断期：生病/受伤/加班/旅行期间按底色标出，不算懈怠。',
                    style: TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.neutral,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (settlement.alert != null) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          SoftCard(
            color: AppColors.calmSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  settlement.alert!.title,
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.calm,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${settlement.alert!.message} ${settlement.alert!.advice}',
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    color: AppColors.inkSoft,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (settlement.positives.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          _SectionTitle('正向 ${settlement.positives.length} 条'),
          for (final ValenceEvent e in settlement.positives)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.gapS),
              child: _PositiveEventCard(event: e),
            ),
        ],
        if (settlement.negatives.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          _SectionTitle('负向 ${settlement.negatives.length} 条'),
          for (final NegativeEvent e in settlement.negatives)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.gapS),
              child: _NegativeEventCard(event: e),
            ),
        ],
        if (settlement.recoveryPlan.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          _SectionTitle('可回补路径'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String line in settlement.recoveryPlan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '· ',
                          style: TextStyle(
                            fontSize: Tokens.fontSmall,
                            color: AppColors.inkFaint,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontSize: Tokens.fontSmall,
                              color: AppColors.inkSoft,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (settlement.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          _SectionTitle('说明'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String note in settlement.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                        height: 1.55,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PositiveEventCard extends StatelessWidget {
  const _PositiveEventCard({required this.event});

  final ValenceEvent event;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  event.behaviorName,
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '+${event.exp.toStringAsFixed(1)} EXP',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 这条"算式"是明细页存在的理由：让人看见分不是拍出来的。
          Text(
            '基础 ${event.baseScore.toStringAsFixed(1)}'
            ' + 精致 ${event.qualityBonus.toStringAsFixed(1)}'
            ' + 效率 ${event.efficiencyBonus.toStringAsFixed(1)}'
            ' = ${event.normalizedScore.toStringAsFixed(1)}'
            ' × 权重 ${event.weight.toStringAsFixed(2)}'
            ' × 状态 ${event.stateMultiplier.toStringAsFixed(2)}'
            ' × 置信 ${event.confidenceWeight.toStringAsFixed(2)}'
            ' × 每点 ${(event.breakdown['exp_per_point'] ?? 0).toStringAsFixed(2)}'
            ' = ${event.exp.toStringAsFixed(1)}',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${event.axis.label} · ${event.confidence.badgeLabel}'
            '${event.estimated ? ' · 估算值' : ''}',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
            ),
          ),
          if (event.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                event.notes.join('；'),
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkSoft,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NegativeEventCard extends StatelessWidget {
  const _NegativeEventCard({required this.event});

  final NegativeEvent event;

  @override
  Widget build(BuildContext context) {
    final bool suppressed = event.suppressed;
    return SoftCard(
      color: suppressed ? AppColors.surfaceMuted : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  event.behaviorName,
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                suppressed ? '不重复扣' : '${event.exp.toStringAsFixed(1)} EXP',
                style: TextStyle(
                  fontSize: Tokens.fontSmall,
                  fontWeight: FontWeight.w700,
                  color: suppressed ? AppColors.inkFaint : AppColors.negative,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '剂量 ${event.doseMinutes.toStringAsFixed(0)} 分钟当量'
            ' · 曲线扣分 ${event.penaltyUnits.toStringAsFixed(2)}'
            ' → EXP ${event.exp.toStringAsFixed(1)}',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.55,
            ),
          ),
          if (suppressed && event.suppressedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '作为「${event.suppressedBy}」的后果记录：同一件事不罚两遍。',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkSoft,
                  height: 1.5,
                ),
              ),
            ),
          if (event.consequences.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                event.consequences.join('；'),
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RawEntries extends StatelessWidget {
  const _RawEntries({required this.entries});

  final List<DraftEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle('原始记录 ${entries.length} 条'),
        for (final DraftEntry e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.gapS),
            child: SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          e.behaviorCode,
                          style: const TextStyle(
                            fontSize: Tokens.fontCaption,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ),
                      Text(
                        '剂量 ${(e.doseFraction * 100).round()}%',
                        style: const TextStyle(
                          fontSize: Tokens.fontCaption,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.interpretation,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.ink,
                      height: 1.45,
                    ),
                  ),
                  if (e.metrics.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        e.metrics.entries
                            .map((MapEntry<String, double> m) =>
                                '${m.key} ${m.value.toStringAsFixed(m.value % 1 == 0 ? 0 : 1)}')
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: Tokens.fontCaption,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.axis.label} · ${e.planStatus.label} · '
                    '${e.confidence.badgeLabel} · 来源 ${e.source}'
                    '${e.revision > 0 ? ' · 第 ${e.revision} 次修订' : ''}',
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.gapS, top: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: Tokens.fontSmall,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}
