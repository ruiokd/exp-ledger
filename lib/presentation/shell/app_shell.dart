import 'dart:async';

import 'package:exp_ledger/core/config/balance_config.dart';
import 'package:exp_ledger/core/log/app_log.dart';
import 'package:exp_ledger/core/theme/tokens.dart';
import 'package:exp_ledger/data/repository/capture_repository.dart';
import 'package:exp_ledger/domain/behaviors/behavior_library.dart';
import 'package:exp_ledger/domain/capture/capture_state_machine.dart';
import 'package:exp_ledger/domain/capture/intent_matcher.dart';
import 'package:exp_ledger/domain/enums.dart';
import 'package:exp_ledger/domain/models/custom_behavior.dart';
import 'package:exp_ledger/domain/models/draft_entry.dart';
import 'package:exp_ledger/domain/models/user_profile.dart';
import 'package:exp_ledger/presentation/capture/capture_controller.dart';
import 'package:exp_ledger/presentation/capture/capture_page.dart';
import 'package:exp_ledger/presentation/chart/chart_page.dart';
import 'package:exp_ledger/presentation/detail/detail_page.dart';
import 'package:exp_ledger/presentation/home/home_page.dart';
import 'package:exp_ledger/presentation/lab/lab_page.dart';
import 'package:exp_ledger/presentation/providers.dart';
import 'package:exp_ledger/presentation/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 四个页面 + 一个入口。
///
/// 底部栏是自绘的，不用 `NavigationBar`：默认组件带 M3 的高度和波纹，
/// 在这个暖白低饱和的界面里会显得比内容还重。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final BehaviorLibrary _library = BehaviorLibrary();

  @override
  void initState() {
    super.initState();
    // 自建项目要先进行为库，采集流程才认得出它。
    // 放 post-frame：开库之后才读得到，且不阻塞首帧。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustom());
  }

  Future<void> _loadCustom() async {
    try {
      final List<CustomBehaviorRecord> records =
          await ref.read(customBehaviorRepositoryProvider).list();
      if (!mounted) return;
      _library.register(
        records.map(customBehaviorDef).toList(growable: false),
      );
      setState(() {});
    } catch (error) {
      logWarn('custom', '自建项目加载失败（内置库照常用）', detail: '$error');
    }
  }
  late final IntentMatcher _matcher = IntentMatcher(_library);
  late final CaptureController _controller = CaptureController(
    machine: CaptureMachine(
      CaptureDeps(
        library: _library,
        matcher: _matcher,
        profile: () => _profile,
        config: () => kDefaultConfig,
        now: () => DateTime.now(),
        newSessionId: () => 's-${DateTime.now().microsecondsSinceEpoch}',
        lastAnswers: (String code) => _lastAnswers[code],
      ),
    ),
    onCommit: (DraftEntry entry) => unawaited(_persist(entry)),
  );

  UserProfile _profile = const UserProfile();
  final Map<String, Map<String, Object?>> _lastAnswers =
      <String, Map<String, Object?>>{};

  int _index = 0;

  static const List<String> _titles = <String>[
    '今天',
    '曲线',
    '明细',
    '实验室',
    '设置',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).load();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // 档案读不到不该拦住首屏：默认档案足够跑完采集流程。
    }
  }

  /// 采集窗口点确认后：落库 → 刷新所有读接口 → 提示一句。
  Future<void> _persist(DraftEntry entry) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final CommitResult result =
          await ref.read(captureRepositoryProvider).commit(entry);
      _lastAnswers[result.entry.behaviorCode] = result.entry.answers;
      if (!mounted) return;
      unawaited(_scheduleConfirmation(result.entry));
      _invalidateAll();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${result.action.label}：${result.entry.interpretation}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('写库失败：$error')),
      );
    }
  }

  /// 确认闭环的发起侧。
  ///
  /// 自报的正向记录第二天问一句"确实做了吗"——不质疑用户，
  /// 只是把"自报"变成"自报 + 一次回看"，置信度才有机会往上走。
  /// 同类型同一天同行为只排一次，不会反复弹。
  Future<void> _scheduleConfirmation(DraftEntry entry) async {
    if (entry.confidence != Confidence.selfReport) return;
    if (entry.planStatus == PlanStatus.missed) return;
    if (entry.valence != Valence.positive) return;

    try {
      await ref.read(confirmationRepositoryProvider).enqueue(
            kind: 'next_day',
            title: '昨天「${entry.interpretation}」还作数吗？',
            day: entry.dayKey.addDays(1),
            behaviorCode: entry.behaviorCode,
            detail: '这条是自报数据。点一下确认，之后这类记录的可信度会更高；'
                '不确认也不扣分。',
          );
    } catch (_) {
      // 排确认失败不该影响已经落库的记录。
    }
  }

  void _invalidateAll() {
    ref.invalidate(todayProvider);
    ref.invalidate(recentDaysProvider);
    ref.invalidate(settingsProvider);
    // family provider 没法整体失效：按天缓存在下面几页里各自 invalidate。
  }

  Future<void> _openCapture() async {
    // 先刷新自建项目：刚建的项目必须能在这次采集里被认出来。
    // register 按 code 去重，重复调用无副作用。
    await _loadCustom();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CapturePage(
          controller: _controller,
          onCommitted: (DraftEntry entry) => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 今日数据一变就推一次桌面小组件。
    // 放在 build 里用 listen（而不是 initState）是为了拿到 provider 的最新值。
    ref.listen<AsyncValue<TodayView>>(todayProvider, (
      AsyncValue<TodayView>? previous,
      AsyncValue<TodayView> next,
    ) {
      final TodayView? view = next.valueOrNull;
      if (view == null) return;
      unawaited(
        ref.read(widgetBridgeProvider).push(
              exp: '${view.netExp >= 0 ? '+' : ''}${view.netExp.toStringAsFixed(1)}',
              level: '${view.snapshot?.level ?? 0}',
              pending: '${view.confirmations.length}',
            ),
      );
    });

    // 自建项目一变就注册进行为库。放在 build 里 listen 而不是流程里 await，
    // 是为了让"在哪新建的"都算数（采集页 / 刻度页 / 以后别处）。
    ref.listen<AsyncValue<List<CustomBehaviorRecord>>>(customBehaviorsProvider,
        (AsyncValue<List<CustomBehaviorRecord>>? previous,
            AsyncValue<List<CustomBehaviorRecord>> next) {
      next.whenData((List<CustomBehaviorRecord> records) {
        _library.register(
          records.map(customBehaviorDef).toList(growable: false),
        );
      });
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(title: _titles[_index]),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const <Widget>[
                  HomePage(),
                  ChartPage(),
                  DetailPage(),
                  LabPage(),
                  SettingsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
      // 居中最下：右下角会压住页面正文（曲线页的免责声明就被它盖住过），
      // 而且"记录一件事"是主操作，不该躲在一角。
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _index == 4
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCapture,
              backgroundColor: AppColors.ink,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('记录一件事'),
            ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onSelect: (int i) => setState(() => _index = i),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: Tokens.fontHeadline,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: Tokens.gapS),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '经验账本',
              style: TextStyle(
                fontSize: Tokens.fontCaption,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自绘底部栏：胶囊选中态 + 细图标，没有波纹扩散。
///
/// 未选中项只显示图标，选中项才展开文字：5 项在 360dp 宽屏上，
/// 全部带文字会直接溢出。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const List<(IconData, String)> _items = <(IconData, String)>[
    (Icons.circle_outlined, '今天'),
    (Icons.show_chart_rounded, '曲线'),
    (Icons.list_alt_rounded, '明细'),
    (Icons.science_outlined, '实验室'),
    (Icons.tune_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            for (var i = 0; i < _items.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(Tokens.radiusChip),
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: Tokens.motionBase,
                  curve: Tokens.motionCurve,
                  padding: EdgeInsets.symmetric(
                    horizontal: i == index ? 14 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(Tokens.radiusChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        _items[i].$1,
                        size: 18,
                        color: i == index ? Colors.white : AppColors.inkSoft,
                      ),
                      if (i == index) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          _items[i].$2,
                          style: const TextStyle(
                            fontSize: Tokens.fontSmall,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
