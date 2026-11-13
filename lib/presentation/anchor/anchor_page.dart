/// 刻度标定总览：一张卡片 = 一个行为的「怎么量 + 估多重 + 实测多重」。
///
/// 页面只读仓储 + 引擎的裁决结果，自己不算任何数字：
/// 权重、空心标记、误差带宽度全来自 `WeightResolution`。
library;

import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/presentation/anchor/anchor_catalog.dart';
import 'package:exp_ledger/presentation/anchor/anchor_onboarding_page.dart';
import 'package:exp_ledger/presentation/anchor/anchor_proposal_page.dart';
import 'package:exp_ledger/presentation/anchor/new_behavior_page.dart';
import 'package:exp_ledger/presentation/anchor/anchor_tier_bar.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnchorPage extends ConsumerWidget {
  const AnchorPage({super.key, this.catalog});

  final AnchorCatalog? catalog;

  AnchorCatalog get _catalog => catalog ?? AnchorCatalog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AnchorCard>> async = ref.watch(anchorCardsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          '刻度标定',
          style: TextStyle(fontSize: Tokens.fontTitle),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace s) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.gapXl),
              child: Text(
                '读不出来：$e',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ),
          data: (List<AnchorCard> cards) => ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.gapL,
              Tokens.gapM,
              Tokens.gapL,
              Tokens.gapXxl,
            ),
            children: <Widget>[
              _intro(),
              const SizedBox(height: Tokens.gapL),
              if (cards.isEmpty)
                _empty()
              else
                ...cards.map((AnchorCard c) => _card(context, ref, c)),
              const SizedBox(height: Tokens.gapL),
              _actions(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(Tokens.gapL),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        child: const Text(
          '你定「怎么量」，系统定「这一档值多少」，实测定「到底多少」。\n'
          '你声明的影响只是先验：权重不超过 50%，图上用空心点 + 虚线带标出来；'
          '一旦有实测证据，先验归零，改用实测反算的档位。\n'
          '「大」这一档锁着——只能由实测解锁。',
          style: TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
      );

  Widget _empty() => Container(
        padding: const EdgeInsets.all(Tokens.gapL),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        child: const Text(
          '还没有刻度卡片。先挑 3–5 项你真正打算追踪的行为，'
          '一项一项定单位——不用一次做完。',
          style: TextStyle(
            fontSize: Tokens.fontBody,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
      );

  Widget _card(BuildContext context, WidgetRef ref, AnchorCard card) {
    final AnchorEngine engine = ref.read(anchorEngineProvider);
    final WeightResolution r = engine.resolve(
      impact: card.impact,
      evidence: card.evidence,
      measurementClass: card.measurementClass,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: Tokens.gapM),
      padding: const EdgeInsets.all(Tokens.gapL),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _catalog.titleOf(card.behaviorId),
                  style: const TextStyle(
                    fontSize: Tokens.fontBody,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _badge(r),
            ],
          ),
          const SizedBox(height: Tokens.gapS),
          Text(
            '一次 = ${card.anchor.unitLabel}',
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.ink,
            ),
          ),
          if (card.anchor.definitionText.isNotEmpty)
            Text(
              card.anchor.definitionText,
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
                height: 1.4,
              ),
            ),
          if (card.anchor.referenceObject.isNotEmpty)
            Text(
              '参照：${card.anchor.referenceObject}',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
              ),
            ),
          const SizedBox(height: Tokens.gapS),
          AnchorTierBar(resolution: r),
          Text(
            '${r.uiNote}　·　权重 ${(r.effectiveWeight * 100).round()}%',
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkSoft,
              height: 1.4,
            ),
          ),
          if (card.measurementClass != MeasurementClass.formula)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.gapXs),
              child: Text(
                card.measurementClass.hint,
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.calm,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: Tokens.gapS),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _recordEvidence(context, ref, card),
              child: const Text(
                '记一次实测',
                style: TextStyle(fontSize: Tokens.fontSmall, color: AppColors.calm),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(WeightResolution r) {
    final bool calibrated = r.isCalibrated;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.gapS,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: calibrated ? AppColors.accentSoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
      ),
      child: Text(
        calibrated ? '实测' : '先验',
        style: TextStyle(
          fontSize: Tokens.fontMicro,
          color: calibrated ? AppColors.accent : AppColors.inkFaint,
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () async {
              final bool? saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => AnchorOnboardingPage(catalog: _catalog),
                ),
              );
              if (saved == true) ref.invalidate(anchorCardsProvider);
            },
            child: const Text('新建 / 继续标定'),
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.divider),
            ),
            onPressed: () async {
              final bool? saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => AnchorProposalPage(catalog: _catalog),
                ),
              );
              if (saved == true) ref.invalidate(anchorCardsProvider);
            },
            child: const Text('想不出单位？让 AI 帮我具体化'),
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.divider),
            ),
            onPressed: () async {
              final CustomBehaviorRecord? created = await Navigator.of(context)
                  .push<CustomBehaviorRecord>(
                MaterialPageRoute<CustomBehaviorRecord>(
                  builder: (_) => const NewBehaviorPage(),
                ),
              );
              if (created != null) {
                ref.invalidate(anchorCardsProvider);
                ref.invalidate(customBehaviorsProvider);
              }
            },
            child: const Text('内置库里没有？新建一个项目'),
          ),
        ),
      ],
    );
  }

  Future<void> _recordEvidence(
    BuildContext context,
    WidgetRef ref,
    AnchorCard card,
  ) async {
    final TextEditingController value = TextEditingController();
    EvidenceKind kind = EvidenceKind.measuredTest;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setLocal) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '实测「${card.anchor.unitLabel}」',
          style: const TextStyle(fontSize: Tokens.fontTitle, color: AppColors.ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '这次实测的值，用同一个单位。写错单位会被降置信度但不阻断。',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: Tokens.gapM),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '实测值',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Tokens.gapM),
            DropdownButton<EvidenceKind>(
              value: kind,
              isExpanded: true,
              items: EvidenceKind.values
                  .map((EvidenceKind k) => DropdownMenuItem<EvidenceKind>(
                        value: k,
                        child: Text(
                          '${k.label}（${k.name}）',
                          style: const TextStyle(fontSize: Tokens.fontSmall),
                        ),
                      ))
                  .toList(growable: false),
              onChanged: (EvidenceKind? v) {
                if (v != null) setLocal(() => kind = v);
              },
            ),
          ],
        ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('记下'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final double? measured = double.tryParse(value.text.trim());
    if (measured == null) {
      _toast(context, '要填数字');
      return;
    }
    final AnchorRepository repo = ref.read(anchorRepositoryProvider);
    try {
      await repo.recordEvidence(
        behaviorId: card.behaviorId,
        kind: kind,
        measuredValue: measured,
        unit: card.anchor.unitLabel,
        performedAt: DateTime.now(),
        rangeId: card.anchor.referenceRangeId,
        measurementClass: card.measurementClass,
      );
      ref.invalidate(anchorCardsProvider);
      final AnchorCard? after = await repo.card(card.behaviorId);
      if (after != null && context.mounted) {
        final WeightResolution r = ref.read(anchorEngineProvider).resolve(
              impact: after.impact,
              evidence: after.evidence,
              measurementClass: after.measurementClass,
            );
        _toast(context, r.uiNote);
      }
    } catch (error) {
      _toast(context, '记录失败：$error');
    }
  }

  void _toast(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.ink),
    );
  }
}
