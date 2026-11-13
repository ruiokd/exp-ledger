/// 网页版 AI 的「具体化」入口。
///
/// 走剪贴板旁路，**不加网络权限**：
///   1. 勾几项想不出怎么量的行为 → 生成请求文本（内含我们的量化公式与硬约束）；
///   2. 复制到网页 AI，把它的回复粘回来；
///   3. 逐条校验（档位封顶、缺依据降档、自造数字打回）；
///   4. 用户逐条确认 → 写成普通先验（和手填完全同一条路）。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/data/data.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/presentation/anchor/anchor_catalog.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnchorProposalPage extends ConsumerStatefulWidget {
  const AnchorProposalPage({super.key, required this.catalog});

  final AnchorCatalog catalog;

  @override
  ConsumerState<AnchorProposalPage> createState() => _AnchorProposalPageState();
}

class _AnchorProposalPageState extends ConsumerState<AnchorProposalPage> {
  final Set<String> _picked = <String>{};
  final TextEditingController _paste = TextEditingController();
  ProposalBundle? _bundle;
  List<ProposalTarget> _targets = const <ProposalTarget>[];
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  AnchorConfig get _config => ref.read(anchorRepositoryProvider).engine.config;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: AppColors.ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          '让 AI 帮我想单位',
          style: TextStyle(fontSize: Tokens.fontTitle),
        ),
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
            _note(),
            const SizedBox(height: Tokens.gapM),
            _picker(),
            const SizedBox(height: Tokens.gapM),
            _step1(),
            const SizedBox(height: Tokens.gapL),
            _step2(),
            if (_bundle != null) ...<Widget>[
              const SizedBox(height: Tokens.gapL),
              _result(_bundle!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _note() => Container(
        padding: const EdgeInsets.all(Tokens.gapL),
        decoration: BoxDecoration(
          color: AppColors.calmSoft,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        child: const Text(
          'AI 只做「具体化」：把说不清的事拆成一个能事后判断真假的一次单位。\n'
          '档位它只能选小 / 中 / 中偏大，「大」要靠实测解锁；没写依据的自动降一档。\n'
          '确认之前，它说的数字不进任何地方。全程走剪贴板，App 不联网。',
          style: TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.ink,
            height: 1.5,
          ),
        ),
      );

  Widget _picker() {
    final List<OnboardingSelection> all = widget.catalog.selections();
    return Wrap(
      spacing: Tokens.gapS,
      runSpacing: Tokens.gapS,
      children: all.map((OnboardingSelection s) {
        final bool on = _picked.contains(s.behaviorId);
        return FilterChip(
          label: Text(s.label, style: const TextStyle(fontSize: Tokens.fontSmall)),
          selected: on,
          selectedColor: AppColors.accentSoft,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: on ? AppColors.accent : AppColors.divider),
          onSelected: (bool v) {
            setState(() {
              if (v && _picked.length < 5) {
                _picked.add(s.behaviorId);
              } else {
                _picked.remove(s.behaviorId);
              }
            });
          },
        );
      }).toList(growable: false),
    );
  }

  Widget _step1() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '① 生成请求文本（复制后贴给网页版 AI）',
            style: TextStyle(fontSize: Tokens.fontBody, color: AppColors.ink),
          ),
          const SizedBox(height: Tokens.gapS),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _picked.isEmpty ? null : _copyRequest,
              child: Text('复制请求文本（已选 ${_picked.length}）'),
            ),
          ),
        ],
      );

  Widget _step2() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '② 把 AI 的回复整段粘回来',
            style: TextStyle(fontSize: Tokens.fontBody, color: AppColors.ink),
          ),
          const SizedBox(height: Tokens.gapS),
          TextField(
            controller: _paste,
            minLines: 5,
            maxLines: 12,
            style: const TextStyle(fontSize: Tokens.fontBody),
            decoration: InputDecoration(
              hintText: '```json [ ... ] ``` 前后有解释也没关系',
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
          const SizedBox(height: Tokens.gapS),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.divider),
              ),
              onPressed: _busy ? null : _decode,
              child: Text(_busy ? '解析中…' : '解析并校验'),
            ),
          ),
        ],
      );

  Widget _result(ProposalBundle bundle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          bundle.summary,
          style: const TextStyle(
            fontSize: Tokens.fontBody,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: Tokens.gapS),
        ...bundle.accepted.map((AiProposal p) => Container(
              margin: const EdgeInsets.only(bottom: Tokens.gapS),
              padding: const EdgeInsets.all(Tokens.gapM),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.catalog.titleOf(p.behaviorId),
                          style: const TextStyle(
                            fontSize: Tokens.fontBody,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        p.appliedTier.label,
                        style: const TextStyle(
                          fontSize: Tokens.fontSmall,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Tokens.gapXs),
                  Text('一次 = ${p.unitLabel}',
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkSoft,
                      )),
                  Text(p.definitionText,
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                      )),
                  Text('理由：${p.rationale}',
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                      )),
                  ...p.notes.map((String n) => Padding(
                        padding: const EdgeInsets.only(top: Tokens.gapXs),
                        child: Text('· $n',
                            style: const TextStyle(
                              fontSize: Tokens.fontMicro,
                              color: AppColors.calm,
                            )),
                      )),
                ],
              ),
            )),
        ...bundle.rejected.map((ProposalRejection r) => Padding(
              padding: const EdgeInsets.only(bottom: Tokens.gapXs),
              child: Text(
                '打回 #${r.index + 1} ${r.code}：${r.message}',
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.negative,
                  height: 1.4,
                ),
              ),
            )),
        if (bundle.hasAccepted) ...<Widget>[
          const SizedBox(height: Tokens.gapM),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _busy ? null : () => _commit(bundle),
              child: Text('确认这 ${bundle.accepted.length} 条'),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 动作

  void _copyRequest() {
    final List<ProposalTarget> targets =
        widget.catalog.targets(_picked.toList(growable: false));
    final String text = AnchorProposalCodec.buildRequestText(
      targets: targets,
      config: _config,
      // 这里用默认配置里的 EXP/点：它只是写给 AI 看的换算说明，
      // 不参与本机计算。改了系数也不影响"你实际得多少"。
      expPerPoint: kDefaultConfig.expPerPoint,
    );
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _targets = targets);
    _snack('请求文本已复制，去网页版 AI 粘贴');
  }

  void _decode() {
    final String raw = _paste.text.trim();
    if (raw.isEmpty) {
      _snack('先把 AI 的回复粘进来');
      return;
    }
    final List<ProposalTarget> targets = _targets.isEmpty
        ? widget.catalog.targets(_picked.toList(growable: false))
        : _targets;
    if (targets.isEmpty) {
      _snack('先在上面勾几项，再生成请求文本');
      return;
    }
    setState(() {
      _busy = true;
      _bundle = AnchorProposalCodec.decode(
        raw,
        targets: targets,
        config: _config,
      );
      _busy = false;
    });
  }

  Future<void> _commit(ProposalBundle bundle) async {
    setState(() => _busy = true);
    final AnchorRepository repo = ref.read(anchorRepositoryProvider);
    final DateTime at = DateTime.now();
    int ok = 0;
    final List<String> failures = <String>[];
    try {
      for (final AiProposal p in bundle.accepted) {
        // 不用 firstOrNull：那是 package:collection 的扩展，这里手写更稳妥。
        MeasurementClass cls = MeasurementClass.subjective;
        for (final ProposalTarget t in _targets) {
          if (t.behaviorId == p.behaviorId) {
            cls = t.measurementClass;
            break;
          }
        }
        final UserAnchor anchor = UserAnchor(
          behaviorId: p.behaviorId,
          unitLabel: p.unitLabel,
          definitionText: p.definitionText,
          referenceObject: p.referenceObject,
          measurementClass: cls,
          referenceRangeId: p.referenceRangeId,
          calibratedAt: at,
        );
        await repo.saveAnchor(anchor, now: at);
        final DeclareResult r = await repo.declareImpact(
          behaviorId: p.behaviorId,
          tier: p.appliedTier,
          at: at,
          reason: 'AI 提议，已确认：${p.rationale}',
        );
        if (r.verdict.ok) {
          ok += 1;
        } else {
          failures.add('${widget.catalog.titleOf(p.behaviorId)}：${r.verdict.message}');
        }
      }
      ref.invalidate(anchorCardsProvider);
      ref.invalidate(anchorResolutionsProvider);
      if (!mounted) return;
      if (failures.isEmpty) {
        Navigator.of(context).pop(true);
      } else {
        _snack('写入 $ok 条，${failures.length} 条没写进去：${failures.first}');
      }
    } catch (error) {
      _snack('写入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
