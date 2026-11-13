/// 新建一个内置行为库没有的项目（「上一堂课」这类）。
///
/// 三步，和刻度标定同一套逻辑：
///   1. 说清这是什么、算哪个轴（用户定语义）；
///   2. 生成请求文本 → 网页 AI 给「单位 + 目标量 + 档位」（AI 做具体化）；
///   3. 粘回来、校验、**用户确认** → 一个事务写行为 + 刻度 + 先验。
///
/// 不走网络：剪贴板旁路，和 `AnchorProposalPage` 一致。
library;

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/domain/anchor/anchor.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NewBehaviorPage extends ConsumerStatefulWidget {
  const NewBehaviorPage({super.key, this.initialName = ''});

  /// 从采集页带过来的原始输入（「上一堂课」），省去用户重打一遍。
  final String initialName;

  @override
  ConsumerState<NewBehaviorPage> createState() => _NewBehaviorPageState();
}

class _NewBehaviorPageState extends ConsumerState<NewBehaviorPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _paste = TextEditingController();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _doseUnit = TextEditingController();

  ProjectAxis _axis = ProjectAxis.discipline;
  BehaviorCategory _category = BehaviorCategory.positive;
  MeasurementClass _cls = MeasurementClass.formula;
  NewBehaviorProposal? _proposal;
  String? _error;
  bool _busy = false;

  AnchorConfig get _config => ref.read(anchorRepositoryProvider).engine.config;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _paste.dispose();
    _target.dispose();
    _doseUnit.dispose();
    super.dispose();
  }

  void _toast(String text) {
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
          '新建项目',
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
            const SizedBox(height: Tokens.gapL),
            _field(_name, '项目名', '例：上一堂课 / 陪孩子写作业'),
            _field(_desc, '一句话说明（可选）', '例：45 分钟的一节正课，含讲与练'),
            const SizedBox(height: Tokens.gapS),
            _label('算哪个轴'),
            _axisChips(),
            const SizedBox(height: Tokens.gapM),
            _label('做了算加分还是扣分'),
            _categoryChips(),
            const SizedBox(height: Tokens.gapM),
            _label('怎么算量'),
            _classChips(),
            const SizedBox(height: Tokens.gapL),
            _step1(),
            const SizedBox(height: Tokens.gapL),
            _step2(),
            if (_proposal != null) ...<Widget>[
              const SizedBox(height: Tokens.gapL),
              _preview(_proposal!),
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
          '内置库没有的项目，可以在这里自己建。\n'
          '系统负责公式（怎么折算成 EXP），AI 负责具体化（一次算多少、量级多大），'
          '你负责拍板。确认之前它说的任何数字都不生效。',
          style: TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.ink,
            height: 1.5,
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.gapS),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.inkFaint,
          ),
        ),
      );

  Widget _axisChips() => Wrap(
        spacing: Tokens.gapS,
        runSpacing: Tokens.gapS,
        children: ProjectAxis.values.map((ProjectAxis a) {
          final bool on = _axis == a;
          return ChoiceChip(
            label: Text(_axisLabel(a),
                style: const TextStyle(fontSize: Tokens.fontSmall)),
            selected: on,
            selectedColor: AppColors.accentSoft,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.accent : AppColors.divider),
            onSelected: (_) => setState(() => _axis = a),
          );
        }).toList(growable: false),
      );

  Widget _categoryChips() => Wrap(
        spacing: Tokens.gapS,
        runSpacing: Tokens.gapS,
        children: BehaviorCategory.values.map((BehaviorCategory c) {
          final bool on = _category == c;
          return ChoiceChip(
            label: Text(_categoryLabel(c),
                style: const TextStyle(fontSize: Tokens.fontSmall)),
            selected: on,
            selectedColor: AppColors.accentSoft,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.accent : AppColors.divider),
            onSelected: (_) => setState(() => _category = c),
          );
        }).toList(growable: false),
      );

  Widget _classChips() => Wrap(
        spacing: Tokens.gapS,
        runSpacing: Tokens.gapS,
        children: MeasurementClass.values.map((MeasurementClass c) {
          final bool on = _cls == c;
          return ChoiceChip(
            label: Text(c.label,
                style: const TextStyle(fontSize: Tokens.fontSmall)),
            selected: on,
            selectedColor: AppColors.accentSoft,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.accent : AppColors.divider),
            onSelected: (_) => setState(() => _cls = c),
          );
        }).toList(growable: false),
      );

  Widget _step1() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('① 生成提示词（复制给网页版 AI）',
              style: TextStyle(fontSize: Tokens.fontBody, color: AppColors.ink)),
          const SizedBox(height: Tokens.gapS),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _busy ? null : _copyRequest,
              child: const Text('复制提示词'),
            ),
          ),
        ],
      );

  Widget _step2() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('② 把 AI 的回复粘回来',
              style: TextStyle(fontSize: Tokens.fontBody, color: AppColors.ink)),
          const SizedBox(height: Tokens.gapS),
          TextField(
            controller: _paste,
            minLines: 5,
            maxLines: 12,
            style: const TextStyle(fontSize: Tokens.fontBody),
            decoration: InputDecoration(
              hintText: '```json { ... } ``` 前后有解释也没关系',
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
              child: const Text('解析并校验'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.gapS),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.negative,
                  height: 1.4,
                ),
              ),
            ),
        ],
      );

  Widget _preview(NewBehaviorProposal p) {
    return Container(
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
                  '${p.name} · ${_axisLabel(p.axis)}',
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
          const SizedBox(height: Tokens.gapS),
          Text('一次 = ${p.unitLabel}',
              style: const TextStyle(
                fontSize: Tokens.fontSmall,
                color: AppColors.ink,
              )),
          Text(p.definitionText,
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
                height: 1.4,
              )),
          Text('理由：${p.rationale}',
              style: const TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
                height: 1.4,
              )),
          ...p.notes.map((String n) => Padding(
                padding: const EdgeInsets.only(top: Tokens.gapXs),
                child: Text('· $n',
                    style: const TextStyle(
                      fontSize: Tokens.fontMicro,
                      color: AppColors.calm,
                      height: 1.4,
                    )),
              )),
          const SizedBox(height: Tokens.gapM),
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
                  controller: _doseUnit,
                  decoration: const InputDecoration(
                    labelText: '单位',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.gapS),
          Text(
            '这两个数决定"做了多少算做满"：实际量 ÷ 一次算多少 = 计入比例。'
            'AI 给的可以改，改完以你的为准。',
            style: const TextStyle(
              fontSize: Tokens.fontMicro,
              color: AppColors.inkFaint,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _busy ? null : () => _create(p),
              child: const Text('创建这个项目'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint) =>
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

  // ---------------------------------------------------------------- 动作

  String _axisLabel(ProjectAxis a) {
    if (a == ProjectAxis.strength) return '体能';
    if (a == ProjectAxis.cardio) return '心肺';
    if (a == ProjectAxis.memory) return '词汇';
    if (a == ProjectAxis.writing) return '写作';
    return '自律';
  }

  String _categoryLabel(BehaviorCategory c) {
    if (c == BehaviorCategory.positive) return '加分';
    if (c == BehaviorCategory.negative) return '扣分';
    return '计划外';
  }

  void _copyRequest() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _toast('先写个项目名');
      return;
    }
    final String text = NewBehaviorCodec.buildNewBehaviorRequestText(
      name: name,
      description: _desc.text.trim(),
      config: _config,
      expPerPoint: kDefaultConfig.expPerPoint,
      axisHint: '我倾向：${_axisLabel(_axis)}；种类：${_categoryLabel(_category)}；'
          '量法：${_cls.label}',
    );
    Clipboard.setData(ClipboardData(text: text));
    logInfo('custom', '生成新项目提示词 $name');
    _toast('提示词已复制，去网页版 AI 粘贴');
  }

  void _decode() {
    final String raw = _paste.text.trim();
    if (raw.isEmpty) {
      _toast('先把 AI 的回复粘进来');
      return;
    }
    final NewBehaviorResult r = NewBehaviorCodec.decodeNewBehavior(
      raw,
      config: _config,
    );
    if (r.proposal == null) {
      setState(() {
        _proposal = null;
        _error = r.error;
      });
      return;
    }
    final NewBehaviorProposal p = r.proposal!;
    _target.text = p.targetDose.toStringAsFixed(
      p.targetDose == p.targetDose.roundToDouble() ? 0 : 1,
    );
    _doseUnit.text = p.doseUnit;
    setState(() {
      _proposal = p;
      _error = null;
      // AI 的具体化优先：单位与轴以它为准，用户在预览里仍可改量。
      _cls = p.measurementClass;
      _axis = p.axis;
      _category = p.category;
    });
  }

  Future<void> _create(NewBehaviorProposal p) async {
    final double? target = double.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      _toast('「一次算多少」要是大于 0 的数字');
      return;
    }
    setState(() => _busy = true);
    try {
      final CustomBehaviorRecord record =
          await ref.read(customBehaviorRepositoryProvider).create(
                name: _name.text.trim().isEmpty ? p.name : _name.text.trim(),
                category: _category,
                axis: _axis,
                measurementClass: _cls,
                unitLabel: p.unitLabel,
                definitionText: p.definitionText,
                targetDose: target,
                doseUnit:
                    _doseUnit.text.trim().isEmpty ? p.doseUnit : _doseUnit.text.trim(),
                tier: p.appliedTier,
                description: _desc.text.trim().isEmpty ? p.description : _desc.text.trim(),
                referenceObject: p.referenceObject,
                referenceRangeId: p.referenceRangeId,
                note: '自建项目（AI 提议已确认）：${p.rationale}',
              );
      ref.invalidate(customBehaviorsProvider);
      ref.invalidate(anchorCardsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(record);
    } catch (error) {
      logError('custom', '创建项目失败', error: error);
      _toast('创建失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
