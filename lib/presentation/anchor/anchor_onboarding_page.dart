/// 首次标定引导：选行为 → 逐个定义单位 → 逐个声明量级 → 写卡片。
///
/// 三条体验约束写在界面上，不只写在文档里：
///   1. 一次只问一件事（页面上永远只有一个问题）；
///   2. 每一步都能"同上次"；
///   3. 随时可以退出——已经标好的会存下来，没标的走自由记录。
library;

import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/presentation/anchor/anchor_catalog.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnchorOnboardingPage extends ConsumerStatefulWidget {
  const AnchorOnboardingPage({super.key, required this.catalog});

  final AnchorCatalog catalog;

  @override
  ConsumerState<AnchorOnboardingPage> createState() =>
      _AnchorOnboardingPageState();
}

class _AnchorOnboardingPageState extends ConsumerState<AnchorOnboardingPage> {
  late OnboardingFlow _flow;
  OnboardingState _state = const OnboardingState();
  final Set<String> _picked = <String>{};
  final TextEditingController _unitCtrl = TextEditingController();
  final TextEditingController _defCtrl = TextEditingController();
  final TextEditingController _refCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _flow = OnboardingFlow(ref.read(anchorEngineProvider));
  }

  @override
  void dispose() {
    _unitCtrl.dispose();
    _defCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingPrompt prompt = _flow.next(_state);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Text(
          _state.stage == OnboardingStage.done ? '刻度卡片' : prompt.title,
          style: const TextStyle(fontSize: Tokens.fontTitle),
        ),
        actions: <Widget>[
          if (_state.stage != OnboardingStage.done)
            TextButton(
              onPressed: _saving ? null : _abandon,
              child: const Text('稍后再标', style: TextStyle(color: AppColors.inkSoft)),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.gapL,
            Tokens.gapM,
            Tokens.gapL,
            Tokens.gapXxl,
          ),
          children: <Widget>[
            if (_state.stage != OnboardingStage.done) _questionCard(prompt),
            if (_state.stage == OnboardingStage.pickBehaviors) ..._pickerBody(),
            if (_state.stage == OnboardingStage.defineUnit) ..._unitBody(prompt),
            if (_state.stage == OnboardingStage.declareTier) ..._tierBody(prompt),
            if (_state.stage == OnboardingStage.done) ..._doneBody(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 问题卡

  Widget _questionCard(OnboardingPrompt prompt) => Container(
        padding: const EdgeInsets.all(Tokens.gapL),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              prompt.question,
              style: const TextStyle(
                fontSize: Tokens.fontBody,
                color: AppColors.ink,
                height: 1.5,
              ),
            ),
            if (prompt.footer.isNotEmpty) ...<Widget>[
              const SizedBox(height: Tokens.gapS),
              Text(
                prompt.footer,
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      );

  // ---------------------------------------------------------------- Step 1

  List<Widget> _pickerBody() {
    final List<OnboardingSelection> all = widget.catalog.selections();
    const int maxPick = 5;
    return <Widget>[
      const SizedBox(height: Tokens.gapL),
      ...all.map((OnboardingSelection s) {
        final bool on = _picked.contains(s.behaviorId);
        final bool blocked = !on && _picked.length >= maxPick;
        return Padding(
          padding: const EdgeInsets.only(bottom: Tokens.gapS),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
            onTap: blocked
                ? () => _snack('最多 $maxPick 项。选多了会变成填表。')
                : () => setState(() {
                      if (on) {
                        _picked.remove(s.behaviorId);
                      } else {
                        _picked.add(s.behaviorId);
                      }
                    }),
            child: Container(
              padding: const EdgeInsets.all(Tokens.gapM),
              decoration: BoxDecoration(
                color: on ? AppColors.accentSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
                border: Border.all(
                  color: on ? AppColors.accent : AppColors.divider,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    on ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: on ? AppColors.accent : AppColors.inkFaint,
                  ),
                  const SizedBox(width: Tokens.gapM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          s.label,
                          style: const TextStyle(
                            fontSize: Tokens.fontBody,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          s.measurementClass.label,
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
          ),
        );
      }),
      const SizedBox(height: Tokens.gapL),
      SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _picked.isEmpty
              ? null
              : () {
                  final List<OnboardingSelection> chosen = all
                      .where((OnboardingSelection s) =>
                          _picked.contains(s.behaviorId))
                      .toList(growable: false);
                  setState(() {
                    _state = _flow.pickBehaviors(_state, chosen);
                  });
                },
          child: Text('下一步（已选 ${_picked.length}）'),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- Step 2

  List<Widget> _unitBody(OnboardingPrompt prompt) {
    final List<Widget> out = <Widget>[
      const SizedBox(height: Tokens.gapL),
      ...prompt.options.map((PromptOption o) => Padding(
            padding: const EdgeInsets.only(bottom: Tokens.gapS),
            child: InkWell(
              borderRadius: BorderRadius.circular(Tokens.radiusButton),
              onTap: () {
                final String unit = o.unitLabel ??
                    _firstUnitOf(o.rangeId) ??
                    '';
                if (unit.isEmpty) {
                  _snack('这个分类还没有中文单位候选，直接在下面写一个。');
                  return;
                }
                setState(() {
                  _state = _flow.defineUnit(
                    _state,
                    at: DateTime.now(),
                    unitLabel: unit,
                    definitionText: _defCtrl.text,
                    referenceObject: _refCtrl.text,
                    rangeId: o.rangeId,
                  );
                });
                _unitCtrl.text = unit;
              },
              child: Container(
                padding: const EdgeInsets.all(Tokens.gapM),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Tokens.radiusButton),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(o.label,
                        style: const TextStyle(
                          fontSize: Tokens.fontBody,
                          color: AppColors.ink,
                        )),
                    if (o.detail.isNotEmpty)
                      Text(o.detail,
                          style: const TextStyle(
                            fontSize: Tokens.fontCaption,
                            color: AppColors.inkFaint,
                          )),
                  ],
                ),
              ),
            ),
          )),
      const SizedBox(height: Tokens.gapM),
      _labeledField(_unitCtrl, '或者自己写一个单位', '例：一次完整家务 / 一页 / 三组'),
      _labeledField(_defCtrl, '什么算一次（能事后判断真假）', '例：不被打断、超过 20 分钟'),
      _labeledField(_refCtrl, '参照物（可选）', '例：相当于散步 30 分钟的疲劳度'),
      const SizedBox(height: Tokens.gapM),
      SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () {
            final String unit = _unitCtrl.text.trim();
            if (unit.isEmpty) {
              _snack('单位不能空着——没有单位就没法算"几次"。');
              return;
            }
            setState(() {
              _state = _flow.defineUnit(
                _state,
                at: DateTime.now(),
                unitLabel: unit,
                definitionText: _defCtrl.text,
                referenceObject: _refCtrl.text,
              );
            });
          },
          child: const Text('用这个单位'),
        ),
      ),
      if (prompt.allowSameAsLast)
        TextButton(
          onPressed: () {
            setState(() {
              _state = _flow.defineUnit(
                _state,
                at: DateTime.now(),
                sameAsLast: true,
              );
            });
          },
          child: const Text('同上次', style: TextStyle(color: AppColors.calm)),
        ),
    ];
    return out;
  }

  String? _firstUnitOf(String? rangeId) {
    final ReferenceRange? r =
        rangeId == null ? null : referenceRangeById(rangeId);
    if (r == null || r.unitSuggestions.isEmpty) return null;
    return r.unitSuggestions.first;
  }

  // ---------------------------------------------------------------- Step 3

  List<Widget> _tierBody(OnboardingPrompt prompt) {
    final ReferenceRange? range = prompt.referenceRange;
    return <Widget>[
      if (range != null) ...<Widget>[
        const SizedBox(height: Tokens.gapM),
        Text(
          '${range.title}\n${range.bandSummary}\n${range.sourceLabel}',
          style: const TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.inkSoft,
            height: 1.5,
          ),
        ),
      ],
      const SizedBox(height: Tokens.gapM),
      ...prompt.options.map((PromptOption o) {
        final ImpactTier? tier = o.tier;
        return Padding(
          padding: const EdgeInsets.only(bottom: Tokens.gapS),
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
            onTap: tier == null ? null : () => _pickTier(tier),
            child: Container(
              padding: const EdgeInsets.all(Tokens.gapM),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(o.label,
                      style: const TextStyle(
                        fontSize: Tokens.fontBody,
                        color: AppColors.ink,
                      )),
                  if (o.detail.isNotEmpty)
                    Text(o.detail,
                        style: const TextStyle(
                          fontSize: Tokens.fontCaption,
                          color: AppColors.inkFaint,
                        )),
                ],
              ),
            ),
          ),
        );
      }),
      if (prompt.allowSameAsLast)
        TextButton(
          onPressed: () {
            final ImpactTier? prev = _prevTier();
            if (prev == null) {
              _snack('上一项还没选档位。');
              return;
            }
            _pickTier(prev);
          },
          child: const Text('同上次', style: TextStyle(color: AppColors.calm)),
        ),
    ];
  }

  ImpactTier? _prevTier() {
    if (_state.cursor <= 0) return null;
    // 列表元素本身非空，所以这里用非空类型——写 `OnboardingSelection?`
    // 会让下一行的 `.behaviorId` 报 unchecked_use_of_nullable_value。
    final OnboardingSelection prev =
        _state.selections[_state.cursor - 1];
    return _state.impacts[prev.behaviorId]?.tier;
  }

  void _pickTier(ImpactTier tier) {
    final ({OnboardingState state, TierChangeVerdict verdict}) r =
        _flow.declareTier(_state, at: DateTime.now(), tier: tier);
    if (!r.verdict.ok) {
      _snack(r.verdict.message);
      return;
    }
    setState(() {
      _state = r.state;
      _unitCtrl.clear();
      _defCtrl.clear();
      _refCtrl.clear();
    });
    if (_state.stage == OnboardingStage.done) _save();
  }

  // ---------------------------------------------------------------- Step 4

  List<Widget> _doneBody() {
    final List<AnchorCard> cards = _flow.buildCards(_state);
    return <Widget>[
      const SizedBox(height: Tokens.gapL),
      ...cards.map((AnchorCard c) => Container(
            margin: const EdgeInsets.only(bottom: Tokens.gapS),
            padding: const EdgeInsets.all(Tokens.gapL),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Tokens.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.catalog.titleOf(c.behaviorId),
                  style: const TextStyle(
                    fontSize: Tokens.fontBody,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: Tokens.gapXs),
                Text(c.unitSummary,
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkSoft,
                    )),
                Text(c.tierSummary,
                    style: const TextStyle(
                      fontSize: Tokens.fontCaption,
                      color: AppColors.inkFaint,
                    )),
              ],
            ),
          )),
      const SizedBox(height: Tokens.gapM),
      SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存这套刻度'),
        ),
      ),
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final AnchorRepository repo = ref.read(anchorRepositoryProvider);
    final DateTime at = DateTime.now();
    try {
      final List<AnchorCard> cards = _flow.buildCards(_state);
      for (final AnchorCard c in cards) {
        await repo.saveAnchor(c.anchor, now: at);
        await repo.declareImpact(
          behaviorId: c.behaviorId,
          tier: c.impact.tier,
          at: at,
          reason: c.impact.note,
        );
      }
      ref.invalidate(anchorCardsProvider);
      ref.invalidate(anchorResolutionsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      _snack('保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _abandon() async {
    setState(() {
      _state = _flow.abandon(_state);
    });
    if (_flow.buildCards(_state).isEmpty) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    await _save();
  }

  Widget _labeledField(
    TextEditingController ctrl,
    String label,
    String hint,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Tokens.gapM),
        child: TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: Tokens.fontBody),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusButton),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
}
