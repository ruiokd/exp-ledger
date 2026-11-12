import 'package:exp_ledger/core/theme/app_theme.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/core/util/date_key.dart';
import 'package:exp_ledger/domain/models/day_settlement.dart';
import 'package:exp_ledger/domain/models/load_index.dart';
import 'package:exp_ledger/domain/models/project_axis.dart';
import 'package:exp_ledger/domain/science/acwr.dart';
import 'package:exp_ledger/presentation/chart/settlement_chart_painter.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主图：历史实线 + 两条未来线 + 置信带 + 两层底色。
///
/// 一条曲线是宿命论，一条上行线是鸡汤。两条并置，用户自己看代价与出路。
class ChartPage extends ConsumerStatefulWidget {
  const ChartPage({super.key});

  @override
  ConsumerState<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends ConsumerState<ChartPage> {
  static const List<_Mode> _modes = <_Mode>[
    _Mode('总经验', null),
    _Mode('体能', ProjectAxis.strength),
    _Mode('心肺', ProjectAxis.cardio),
    _Mode('词汇', ProjectAxis.memory),
    _Mode('写作', ProjectAxis.writing),
    _Mode('自律', ProjectAxis.discipline),
  ];

  static const List<int> _ranges = <int>[30, 90, 365];

  int _modeIndex = 0;
  int _rangeDays = 90;

  _Mode get _mode => _modes[_modeIndex];

  @override
  Widget build(BuildContext context) {
    final DayKey today = DayKey.today();
    final DayKey from = today.addDays(-(_rangeDays - 1));
    final AsyncValue<ChartData> async =
        ref.watch(chartProvider((from: from, to: today)));

    return RefreshIndicator(
      color: AppColors.calm,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(chartProvider((from: from, to: today)));
        await ref.read(chartProvider((from: from, to: today)).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
        children: <Widget>[
          _ModeChips(
            modes: _modes,
            index: _modeIndex,
            onSelect: (int i) => setState(() => _modeIndex = i),
          ),
          const SizedBox(height: Tokens.gapS),
          Row(
            children: <Widget>[
              const Text(
                '区间',
                style: TextStyle(
                  fontSize: Tokens.fontCaption,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(width: Tokens.gapS),
              for (final int d in _ranges)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _SmallChip(
                    label: '$d 天',
                    selected: _rangeDays == d,
                    onTap: () => setState(() => _rangeDays = d),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.gapM),
          SoftCard(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: async.when(
              loading: () => const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace stack) => SizedBox(
                height: 280,
                child: Center(
                  child: Text(
                    '曲线读不出来：$error',
                    style: const TextStyle(
                      fontSize: Tokens.fontSmall,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
              data: (ChartData data) {
                final ChartModel? model = _buildModel(data);
                if (model == null) {
                  return const SizedBox(
                    height: 280,
                    child: Center(
                      child: Text(
                        '还没有任何结算记录。\n记一条，这条线才开始有历史。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: Tokens.fontSmall,
                          color: AppColors.inkFaint,
                          height: 1.6,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: SettlementChartPainter(
                          model: model,
                          historyColor: AppColors.ink,
                          correctColor: AppColors.accent,
                          maintainColor: AppColors.negative,
                        ),
                      ),
                    ),
                    const SizedBox(height: Tokens.gapS),
                    _Legend(hasForecast: model.hasForecast),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Tokens.gapM),
          async.maybeWhen(
            data: (ChartData data) => _InsightCard(data: data, mode: _mode),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 把仓储数据装成 painter 要的形状。
  ChartModel? _buildModel(ChartData data) {
    if (data.snapshots.isEmpty) return null;

    final List<DayKey> days = <DayKey>[];
    final List<double> values = <double>[];
    for (final AbilitySnapshot snap in data.snapshots) {
      days.add(snap.day);
      values.add(
        _mode.axis == null
            ? snap.totalExp
            : snap.abilityOf(_mode.axis!.name),
      );
    }

    final List<ForecastPoint> points = _mode.axis == null
        ? const <ForecastPoint>[]
        : (data.forecast[_mode.axis!] ?? const <ForecastPoint>[])
            .where((ForecastPoint p) => p.isProjection)
            .toList();

    final Set<DayKey> risk = <DayKey>{
      for (final LoadIndex l in data.loads)
        if (bandFor(l.acwr, data.config).isRisk) l.day,
    };
    final Set<DayKey> interruption = <DayKey>{
      for (final DaySettlement s in data.settlements)
        if (s.isInterruption) s.dayKey,
    };

    final List<double> all = <double>[
      ...values,
      ...points.map((ForecastPoint p) => p.low),
      ...points.map((ForecastPoint p) => p.high),
    ];
    double minY = all.reduce((double a, double b) => a < b ? a : b);
    double maxY = all.reduce((double a, double b) => a > b ? a : b);
    final double span = maxY - minY;
    final double pad = span < 10 ? 5 : span * 0.12;
    minY = (minY - pad).clamp(0, 100000).toDouble();
    maxY = maxY + pad;

    return ChartModel(
      days: days,
      values: values,
      forecastDays: points.map((ForecastPoint p) => p.day).toList(),
      maintain: points.map((ForecastPoint p) => p.maintain).toList(),
      correct: points.map((ForecastPoint p) => p.correct).toList(),
      low: points.map((ForecastPoint p) => p.low).toList(),
      high: points.map((ForecastPoint p) => p.high).toList(),
      riskDays: risk,
      interruptionDays: interruption,
      today: data.today,
      minY: minY,
      maxY: maxY,
    );
  }
}

class _ModeChips extends StatelessWidget {
  const _ModeChips({
    required this.modes,
    required this.index,
    required this.onSelect,
  });

  final List<_Mode> modes;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < modes.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SmallChip(
                label: modes[i].label,
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusChip),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Tokens.motionFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: Tokens.fontCaption,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.hasForecast});

  final bool hasForecast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: Tokens.gapM,
        runSpacing: 6,
        children: <Widget>[
          const _LegendDot(color: AppColors.ink, label: '已发生'),
          if (hasForecast) ...<Widget>[
            const _LegendDot(color: AppColors.negative, label: '维持现状'),
            const _LegendDot(color: AppColors.accent, label: '立即修正'),
            _LegendDot(
              color: AppColors.calm.withOpacity(0.35),
              label: '估计区间',
            ),
          ],
          _LegendDot(color: AppColors.negativeSoft, label: '负荷风险日'),
          _LegendDot(color: AppColors.neutralSoft, label: '中断期'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: Tokens.fontCaption,
            color: AppColors.inkFaint,
          ),
        ),
      ],
    );
  }
}

/// 数字摘要 + 必须一起出现的免责说明。
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.data, required this.mode});

  final ChartData data;
  final _Mode mode;

  @override
  Widget build(BuildContext context) {
    final List<AbilitySnapshot> snaps = data.snapshots;
    if (snaps.isEmpty) return const SizedBox.shrink();

    final AbilitySnapshot latest = snaps.last;
    final double now = mode.axis == null
        ? latest.totalExp
        : latest.abilityOf(mode.axis!.name);

    final List<ForecastPoint> points = mode.axis == null
        ? const <ForecastPoint>[]
        : (data.forecast[mode.axis!] ?? const <ForecastPoint>[]);

    final ForecastPoint? last = points.isEmpty ? null : points.last;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${mode.label} · 今天',
                style: const TextStyle(
                  fontSize: Tokens.fontSmall,
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                now.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: Tokens.fontTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (last != null) ...<Widget>[
            const SizedBox(height: Tokens.gapS),
            Text(
              '${last.day.diffDays(data.today).clamp(0, 999).toInt()} 天后：'
              '维持现状约 ${last.maintain.toStringAsFixed(1)}，'
              '立即修正约 ${last.correct.toStringAsFixed(1)}'
              '（区间 ${last.low.toStringAsFixed(0)}–${last.high.toStringAsFixed(0)}）',
              style: const TextStyle(
                fontSize: Tokens.fontSmall,
                color: AppColors.inkSoft,
                height: 1.55,
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: Tokens.gapS),
            const Text(
              '总经验不外推：它由每天的结算累加，预测一条"以后会有多少级"'
              '没有可查证的依据，不如只看已经发生的。',
              style: TextStyle(
                fontSize: Tokens.fontSmall,
                color: AppColors.inkFaint,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: Tokens.gapS),
          const Text(
            '预测是概率性估计，不是承诺；负荷指标源自竞技体育研究，'
            '用于日常记录属外推近似，不构成诊断。',
            style: TextStyle(
              fontSize: Tokens.fontCaption,
              color: AppColors.inkFaint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mode {
  const _Mode(this.label, this.axis);

  final String label;
  final ProjectAxis? axis;
}
