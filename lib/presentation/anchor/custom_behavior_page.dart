/// 自建项目的管理页：列出、编辑、删除。
///
/// 为什么单独一页：这些项目的**定义**（目标量、折算方式）会改，
/// 但它们不该混在采集流程里改——采集是"记录"，这里是"改尺子"。
///
/// 编辑走 `CustomBehaviorRepository.update`，一个事务同时改
/// `custom_behavior.target_dose` 与 `behavior_quant_spec.target_dose`（两个真源）。
library;

import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/quant/quant.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/presentation/quant/shape_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomBehaviorPage extends ConsumerWidget {
  const CustomBehaviorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CustomBehaviorRecord>> async =
        ref.watch(customBehaviorsProvider);
    final Map<String, QuantSpec> specs =
        ref.watch(customQuantSpecsProvider).valueOrNull ??
            const <String, QuantSpec>{};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          '自建项目',
          style: TextStyle(fontSize: Tokens.fontTitle),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace _) => Center(
            child: Text(
              '读不到项目列表：$e',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          data: (List<CustomBehaviorRecord> records) {
            if (records.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(Tokens.gapL),
                  child: Text(
                    '还没有自建项目。\n'
                    '在刻度标定页或采集页说一件内置库里没有的事，就能建一个。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkFaint,
                      height: 1.6,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(Tokens.gapM),
              itemCount: records.length,
              separatorBuilder: (BuildContext ctx, int index) =>
                  const SizedBox(height: Tokens.gapXs),
              itemBuilder: (BuildContext context, int i) => _Row(
                record: records[i],
                spec: specs[records[i].code],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.record, this.spec});

  final CustomBehaviorRecord record;
  final QuantSpec? spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String shape = spec?.shape.kind.label ?? DoseShape.linear.label;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      padding: const EdgeInsets.fromLTRB(
        Tokens.gapM,
        Tokens.gapS,
        Tokens.gapXs,
        Tokens.gapS,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.name,
                  style: const TextStyle(
                    fontSize: Tokens.fontBody,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '一次 ${_fmt(record.targetDose)}${record.doseUnit} · $shape · '
                  '${record.axis.label}',
                  style: const TextStyle(
                    fontSize: Tokens.fontMicro,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppColors.inkFaint,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.background,
              builder: (_) => _EditSheet(record: record, spec: spec),
            ),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.inkFaint,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('删掉这个项目？'),
        content: Text(
          '「${record.name}」以及它的刻度、量化口径会一起删除。\n'
          '已经记下的历史记录不会消失。',
          style: const TextStyle(fontSize: Tokens.fontCaption, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不删'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删掉'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(customBehaviorRepositoryProvider).remove(record.code);
      ref.invalidate(customBehaviorsProvider);
      ref.invalidate(customQuantSpecsProvider);
      ref.invalidate(anchorCardsProvider);
    } catch (error) {
      logError('custom', '删除项目失败', error: error);
    }
  }
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.record, this.spec});

  final CustomBehaviorRecord record;
  final QuantSpec? spec;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.record.name);
  late final TextEditingController _target =
      TextEditingController(text: _fmt(widget.record.targetDose));
  late final TextEditingController _unit =
      TextEditingController(text: widget.record.doseUnit);
  late DoseShape _shape = widget.spec?.shape.kind ?? DoseShape.linear;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.gapM,
        right: Tokens.gapM,
        top: Tokens.gapM,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.gapM,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '改「${widget.record.name}」',
              style: const TextStyle(
                fontSize: Tokens.fontTitle,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: Tokens.gapM),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名字',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Tokens.gapS),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '一次算多少',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.gapS),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: '单位',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.gapM),
            ShapePicker(
              value: _shape,
              onChanged: (DoseShape s) => setState(() => _shape = s),
            ),
            const SizedBox(height: Tokens.gapM),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('不改了'),
                  ),
                ),
                const SizedBox(width: Tokens.gapS),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: _busy ? null : _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final double? target = double.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('「一次算多少」要是大于 0 的数字')),
      );
      return;
    }
    final String unit = _unit.text.trim().isEmpty
        ? widget.record.doseUnit
        : _unit.text.trim();

    // 保留原来的维度归属：这次只改形状与目标量，不该顺手把"这条算哪个维度"改掉。
    final List<ImpactShare> impact =
        (widget.spec != null && widget.spec!.impact.isNotEmpty)
            ? widget.spec!.impact
            : <ImpactShare>[
                ImpactShare(
                  axisKey: widget.record.axis.name,
                  axisLabel: widget.record.axis.label,
                  kind: AxisKind.ability,
                  share: 1,
                ),
              ];

    final QuantSpec quant = QuantSpec(
      behaviorCode: widget.record.code,
      measureKind: widget.spec?.measureKind ?? MeasureKind.guessFromUnit(unit),
      measureUnit: unit,
      shape: DoseShapeSpec(kind: _shape),
      targetDose: target,
      impact: impact,
      citation: '编辑时选择折算方式：${_shape.label}',
      source: 'userPrior',
    );

    setState(() => _busy = true);
    try {
      await ref.read(customBehaviorRepositoryProvider).update(
            code: widget.record.code,
            name: _name.text,
            targetDose: target,
            doseUnit: unit,
            quant: quant,
          );
      ref.invalidate(customBehaviorsProvider);
      ref.invalidate(customQuantSpecsProvider);
      ref.invalidate(anchorCardsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      logError('custom', '保存项目失败', error: error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
