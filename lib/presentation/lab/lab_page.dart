import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/data/repository/config_repository.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 数值实验室。
///
/// 这不是"给用户玩的开关"，是让公式**可查证**：
/// 觉得"1 点有效分换 0.5 EXP 太高"？把它调低，看整条曲线怎么变。
/// 每个系数都写着它管什么，改完立刻重算，图上立刻能看出差异。
///
/// 三条约束：
///   1. 只允许改 `BalanceConfig.toMap()` 里存在的键（`ConfigRepository.set` 会拒）；
///   2. 改完必须重算，否则图表和配置互相矛盾；
///   3. 每一项都能一键回到默认值。
class LabPage extends ConsumerStatefulWidget {
  const LabPage({super.key});

  @override
  ConsumerState<LabPage> createState() => _LabPageState();
}

class _LabPageState extends ConsumerState<LabPage> {
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Map<String, ({double current, double baseline})>> async =
        ref.watch(configDiffProvider);

    return RefreshIndicator(
      color: AppColors.calm,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(configDiffProvider);
        await ref.read(configDiffProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => ListView(
          padding: Tokens.pagePadding,
          children: <Widget>[
            SoftCard(
              child: Text(
                '读不出系数：$error',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
        data: (Map<String, ({double current, double baseline})> diff) =>
            ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: <Widget>[
            const _IntroCard(),
            const SizedBox(height: Tokens.gapM),
            _HeaderCard(
              busy: _busy,
              status: _status,
              changedCount: diff.entries
                  .where(
                    (MapEntry<String, ({double current, double baseline})> e) =>
                        (e.value.current - e.value.baseline).abs() > 1e-9,
                  )
                  .length,
              onResetAll: _resetAll,
            ),
            const SizedBox(height: Tokens.gapM),
            for (final _Group group in _groups)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.gapM),
                child: _GroupCard(
                  group: group,
                  diff: diff,
                  onEdit: (String key) => _edit(key, diff[key]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetAll() async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: const Text('全部恢复默认？'),
        content: const Text(
          '所有被改过的系数都会回到默认值，然后重算最近 90 天。',
          style: TextStyle(
            fontSize: Tokens.fontSmall,
            color: AppColors.inkSoft,
            height: 1.6,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(configRepositoryProvider).resetAll();
      final int days = await _recompute();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '已全部恢复默认，重算 $days 天';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '失败：$error';
      });
    }
  }

  Future<void> _edit(
    String key,
    ({double current, double baseline})? entry,
  ) async {
    if (entry == null) return;
    final ({double value, bool reset})? result =
        await showModalBottomSheet<({double value, bool reset})>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radiusSheet),
        ),
      ),
      builder: (BuildContext ctx) => _ConfigEditorSheet(
        configKey: key,
        label: _labelOf(key),
        hint: _hintOf(key),
        current: entry.current,
        baseline: entry.baseline,
      ),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      ConfigWriteResult write;
      if (result.reset) {
        await ref.read(configRepositoryProvider).reset(key);
        write = const ConfigWriteResult(ok: true, key: '*');
      } else {
        write = await ref.read(configRepositoryProvider).set(key, result.value);
      }

      if (!write.ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = write.message ?? '写不进去';
        });
        return;
      }

      final int days = await _recompute();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '${result.reset ? '已恢复默认' : '已应用'}'
            '${result.reset ? '' : ' ${_fmt(result.value)}'}，重算 $days 天';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '失败：$error';
      });
    }
  }

  /// 改系数 → 重算 → 让所有读接口失效。
  /// 顺序不能反：先重算，再 invalidate，否则页面会先拿到旧数据再刷新。
  Future<int> _recompute() async {
    final DayKey from = DayKey.today().addDays(-89);
    final run = await ref.read(settlementRepositoryProvider).recomputeFrom(from);
    ref.invalidate(todayProvider);
    ref.invalidate(configDiffProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(recentDaysProvider);
    return run.count;
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '为什么可以改',
            style: TextStyle(
              fontSize: Tokens.fontBody,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '这套账本的每个数字都来自一条公式。公式里有系数，系数就是假设。'
            '把假设摊开在桌面上、能改、能看后果——比藏在一个"科学"的名头后面诚实。',
            style: TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          const Text(
            '改完会重算最近 90 天：历史记录不变，但结算、快照、预测全部重跑。'
            '所以同一批数据在两套系数下会给出两条曲线——这正好证明分是人定的。',
            style: TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.busy,
    required this.status,
    required this.changedCount,
    required this.onResetAll,
  });

  final bool busy;
  final String status;
  final int changedCount;
  final Future<void> Function() onResetAll;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: changedCount > 0 ? AppColors.accentSoft : AppColors.surfaceMuted,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  changedCount == 0 ? '当前全部为默认系数' : '$changedCount 项被改过',
                  style: const TextStyle(
                    fontSize: Tokens.fontSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '正在重算…',
                      style: TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  )
                else if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: Tokens.fontCaption,
                        color: AppColors.inkFaint,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (changedCount > 0)
            TextButton(
              onPressed: busy ? null : () => onResetAll(),
              child: const Text('全恢复'),
            ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.diff,
    required this.onEdit,
  });

  final _Group group;
  final Map<String, ({double current, double baseline})> diff;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final List<String> keys = group.keys.where(diff.containsKey).toList();
    if (keys.isEmpty) return const SizedBox.shrink();

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            group.title,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            group.note,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.45,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          for (final String key in keys)
            _ConfigRow(
              configKey: key,
              label: _labelOf(key),
              current: diff[key]!.current,
              baseline: diff[key]!.baseline,
              onTap: () => onEdit(key),
            ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    required this.configKey,
    required this.label,
    required this.current,
    required this.baseline,
    required this.onTap,
  });

  final String configKey;
  final String label;
  final double current;
  final double baseline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool changed = (current - baseline).abs() > 1e-9;
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusSmall),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    configKey,
                    style: const TextStyle(
                      fontSize: Tokens.fontMicro,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _fmt(current),
              style: TextStyle(
                fontSize: Tokens.fontSmall,
                fontWeight: FontWeight.w700,
                color: changed ? AppColors.calm : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑面板：滑杆负责"大概往哪调"，输入框负责"精确到小数第几位"。
class _ConfigEditorSheet extends StatefulWidget {
  const _ConfigEditorSheet({
    required this.configKey,
    required this.label,
    required this.hint,
    required this.current,
    required this.baseline,
  });

  final String configKey;
  final String label;
  final String hint;
  final double current;
  final double baseline;

  @override
  State<_ConfigEditorSheet> createState() => _ConfigEditorSheetState();
}

class _ConfigEditorSheetState extends State<_ConfigEditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: _fmt(widget.current));
  late double _value = widget.current;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 滑杆范围跟着默认值走：太小看不见差异，太大滑不准。
  double get _max {
    final double b = widget.baseline;
    if (b <= 0) return 1;
    return b * 3;
  }

  double get _min => 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: Tokens.fontTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          Text(
            widget.configKey,
            style: const TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: Tokens.gapS),
          Text(
            widget.hint,
            style: const TextStyle(
              fontSize: Tokens.fontSmall,
              color: AppColors.inkSoft,
              height: 1.55,
            ),
          ),
          const SizedBox(height: Tokens.gapL),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: '精确值',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Tokens.radiusButton),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (String raw) {
                    final double? parsed = double.tryParse(raw);
                    if (parsed == null) return;
                    setState(() => _value = parsed);
                  },
                ),
              ),
              const SizedBox(width: Tokens.gapM),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Text(
                    '默认',
                    style: TextStyle(
                      fontSize: Tokens.fontMicro,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  Text(
                    _fmt(widget.baseline),
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Tokens.gapM),
          Slider(
            value: _value.clamp(_min, _max).toDouble(),
            min: _min,
            max: _max,
            divisions: 60,
            activeColor: AppColors.calm,
            onChanged: (double v) {
              setState(() {
                _value = v;
                _controller.text = _fmt(v);
              });
            },
          ),
          Row(
            children: <Widget>[
              Text(
                '0',
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.inkFaint,
                ),
              ),
              const Spacer(),
              Text(
                _fmt(_max),
                style: const TextStyle(
                  fontSize: Tokens.fontMicro,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.gapM),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(
                  (value: widget.baseline, reset: true),
                ),
                child: const Text('恢复默认'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusButton),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(
                  (value: _value, reset: false),
                ),
                child: const Text('应用并重算'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 系数分组。分组只影响阅读顺序，不影响计算。
class _Group {
  const _Group(this.title, this.note, this.keys);

  final String title;
  final String note;
  final List<String> keys;
}

const List<_Group> _groups = <_Group>[
  _Group(
    '加减分',
    '一分值多少经验、精致与效率各自能加多少。改这里，所有正向记录立刻变。',
    <String>[
      'expPerPoint',
      'partialDoseExponent',
      'qualityWeight',
      'qualityBonusCap',
      'efficiencyWeight',
      'efficiencyBonusCap',
    ],
  ),
  _Group(
    '负向曲线',
    '剂量 → 扣分的三段曲线。k1 管轻微越界，k3 管深度越界，指数管陡峭程度。',
    <String>[
      'negK1',
      'negK2',
      'negK3',
      'negLinearZoneMinutes',
      'negAccelZoneMinutes',
      'negScaleExp',
    ],
  ),
  _Group(
    '状态变量',
    '睡债 / 损伤 / 恢复债怎么打折，以及它们每天怎么衰减。',
    <String>[
      'sleepDebtPenaltyPerHour',
      'sleepDebtPenaltyCap',
      'damagePenaltyPerLoad',
      'damagePenaltyCap',
      'recoveryPenaltyPerUnit',
      'recoveryPenaltyCap',
      'sleepDebtDecayPerNight',
      'damageDecayPerDay',
    ],
  ),
  _Group(
    '等级',
    '第 n 级要多少经验、缓冲池能吸收多少负向。',
    <String>['levelBaseExp', 'levelExponent', 'levelBufferRatio'],
  ),
  _Group(
    '快照与预测',
    '五维怎么涨、怎么回落，完整度窗口多长，预测看多远。',
    <String>[
      'abilityBaseline',
      'abilityCap',
      'abilityPerExp',
      'abilityDecayPerDay',
      'completenessWindowDays',
      'forecastHorizonDays',
      'forecastStepDays',
      'srpeDefaultRpe',
    ],
  ),
  _Group(
    '记忆',
    '间隔重复的增长率与间隔上限。',
    <String>[
      'memoryReviewBaseDays',
      'memoryReviewGrowth',
      'memoryReviewMaxDays',
      'memoryStrengthBase',
      'memoryActiveRecallBoost',
      'memoryReviewBoost',
      'memoryCoverageThreshold',
    ],
  ),
  _Group(
    '能量与负荷',
    'BMR/PAL、TEF、EPOC 与 MET 换算。摄入热量还没有采集入口，先放着。',
    <String>[
      'tefFactor',
      'epocFactor',
      'neatPalSedentary',
      'neatPalActive',
      'metResistanceModerate',
      'metResistanceVigorous',
      'metCardioFactor',
    ],
  ),
  _Group(
    '训练剂量',
    '组间休息、每次动作耗时、有效组比例、RIR 阈值。',
    <String>[
      'restSecondsPerSet',
      'secondsPerRep',
      'minEffectiveSetFraction',
      'rirFullThreshold',
    ],
  ),
  _Group(
    '超额路由',
    '计划外加练怎么判：疲劳、ACWR、恢复间隔都过了才算"有益超额"，否则转成损伤。',
    <String>['overshootExponent', 'overshootDamageFactor', 'damageGain'],
  ),
  _Group(
    '项目权重',
    '五维折算 EXP 时的权重。0.7 的写作和 1.0 的体能，同样的完成度给不同的分。',
    <String>[
      'weightStrength',
      'weightCardio',
      'weightMemory',
      'weightWriting',
      'weightMind',
      'weightSleep',
      'weightNutrition',
      'weightRestraint',
    ],
  ),
  _Group(
    'ACWR 阈值',
    '急性:慢性负荷比的三条线。竞技体育外推，只作趋势提示。',
    <String>['acwrLowRiskMin', 'acwrLowRiskMax', 'acwrWarningMax'],
  ),
];

const Map<String, String> _labels = <String, String>{
  'expPerPoint': '1 点有效分换多少 EXP',
  'partialDoseExponent': '部分剂量的折算指数',
  'qualityWeight': '精致加成权重',
  'qualityBonusCap': '精致加成上限',
  'efficiencyWeight': '效率加成权重',
  'efficiencyBonusCap': '效率加成上限',
  'negK1': '负向曲线：线性段斜率',
  'negK2': '负向曲线：加速段系数',
  'negK3': '负向曲线：深度段系数',
  'negLinearZoneMinutes': '线性区上限（分钟）',
  'negAccelZoneMinutes': '加速区上限（分钟）',
  'negScaleExp': '负向 → EXP 的换算倍数',
  'sleepDebtPenaltyPerHour': '每睡债小时折价',
  'sleepDebtPenaltyCap': '睡债折价上限',
  'damagePenaltyPerLoad': '每点损伤负荷折价',
  'damagePenaltyCap': '损伤折价上限',
  'recoveryPenaltyPerUnit': '每点恢复债折价',
  'recoveryPenaltyCap': '恢复债折价上限',
  'sleepDebtDecayPerNight': '睡债每晚回补比例',
  'damageDecayPerDay': '损伤每日衰减比例',
  'levelBaseExp': '等级基数 EXP',
  'levelExponent': '等级成长指数',
  'levelBufferRatio': '缓冲池相对本级的比例',
  'abilityBaseline': '五维初始基线',
  'abilityCap': '五维上限',
  'abilityPerExp': '每点 EXP 折算多少能力',
  'abilityDecayPerDay': '能力每日回落比例',
  'completenessWindowDays': '完整度统计窗口（天）',
  'forecastHorizonDays': '预测时长（天）',
  'forecastStepDays': '预测打点步长（天）',
  'srpeDefaultRpe': '缺省 RPE（没填强度时）',
  'memoryReviewBaseDays': '首次复习间隔（天）',
  'memoryReviewGrowth': '复习间隔增长率',
  'memoryReviewMaxDays': '复习间隔上限（天）',
  'memoryStrengthBase': '记忆强度基数',
  'memoryActiveRecallBoost': '主动回忆的间隔加成',
  'memoryReviewBoost': '重读式复习的间隔加成',
  'memoryCoverageThreshold': '覆盖度阈值',
  'tefFactor': '食物热效应系数',
  'epocFactor': '运动后过量氧耗系数',
  'neatPalSedentary': '久坐日 PAL',
  'neatPalActive': '活动日 PAL',
  'metResistanceModerate': '抗阻（中等）MET',
  'metResistanceVigorous': '抗阻（高强度）MET',
  'metCardioFactor': '有氧 MET 系数',
  'restSecondsPerSet': '组间休息（秒）',
  'secondsPerRep': '每次动作耗时（秒）',
  'minEffectiveSetFraction': '有效组最低比例',
  'rirFullThreshold': 'RIR 满额阈值',
  'acwrLowRiskMin': 'ACWR 低风险下界',
  'acwrLowRiskMax': 'ACWR 低风险上界',
  'acwrWarningMax': 'ACWR 警戒上界',
  'weightStrength': '体能权重',
  'weightCardio': '心肺权重',
  'weightMemory': '词汇权重',
  'weightWriting': '写作权重',
  'weightMind': '心态权重',
  'weightSleep': '睡眠权重',
  'weightNutrition': '营养权重',
  'weightRestraint': '节制权重',
  'defaultSleepNeedHours': '默认睡眠需求（小时）',
  'overshootExponent': '超额计分的边际递减指数',
  'overshootDamageFactor': '超额转损伤的系数',
  'damageGain': '风险事件 → 损伤负荷增益',
};

const Map<String, String> _hints = <String, String>{
  'expPerPoint': '默认 0.5：满分日约 50 EXP 量级。调低 → 成长变慢，等级更难爬。',
  'abilityPerExp': '默认 0.25：40 EXP 换 10 点能力。调高 → 五维涨得更快。',
  'abilityDecayPerDay': '默认 0.004：一周不动掉约 3%。它决定"不用会不会退"。',
  'negScaleExp': '默认 3：曲线扣分乘这个倍数才变成 EXP。它是负向的总闸门。',
  'levelBaseExp': '默认 100：第 1 级 100 EXP，之后按指数增长。',
  'levelBufferRatio': '默认 0.35：缓冲池最多吸收本级跨度的三成五。',
  'forecastHorizonDays': '默认 90 天。调短 → 预测更保守，置信带更窄。',
  'srpeDefaultRpe': '默认 6/10。记录里没写 RPE 也没写 RIR 时按这个估。',
  'acwrLowRiskMax': '默认 1.3：超过就是"负荷爬升偏快"。这是外推阈值，不是诊断线。',
  'memoryReviewGrowth': '默认 2.3：间隔按这个倍数增长，涨到上限为止。',
  'overshootExponent': '默认 0.6：超额的边际价值递减，但永不归零。',
  'overshootDamageFactor': '默认 0.35：判定为过量时，超额剂量转成多少损伤。',
  'weightStrength': '默认 1.0。调低就是把这项成长"打折"，不是否定你的努力。',
};

String _labelOf(String key) => _labels[key] ?? key;

String _hintOf(String key) =>
    _hints[key] ?? '这是 $key 的系数。默认值见下方，改动会立刻重算。';

/// 系数显示格式：太小用科学计数，其余最多 4 位小数。
String _fmt(double v) {
  if (v != 0 && v.abs() < 0.001) return v.toStringAsExponential(2);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );
}
