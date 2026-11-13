/// 维度注册表：内置 5 维 + 用户新增维度的**只读视图**。
///
/// 这一版是纯新增，不改 `ProjectAxis`，也不改 `decay_model` / `snapshot_builder`。
/// 它存在的理由是先把「维度是什么」这件事说清楚：
///
///   * `ability`     —— 能力维度：可累积、会衰减、进主曲线。必须有衰减常数依据。
///   * `experience`  —— 体验维度：不累积、不给能力值，只记频次与主观分。
///
/// 内置 5 维的 `decayTauDays` 是从 `decay_model.detrainTau` 抄过来的**镜像**。
/// 两个真源并存是暂时的：v1.2.1 接线时让 `detrainTau` 反过来查这张表，
/// 现在靠 `test/quant/axis_registry_test.dart` 里的一条断言防止两边漂开。
library;

import 'package:exp_ledger/domain/models/project_axis.dart';

/// 维度的量纲类型。决定这条维度能不能进主曲线。
enum AxisKind {
  /// 能力：练出来的存量，有衰减，进主曲线。
  ability('能力', '会累积也会衰减，画在主曲线上'),

  /// 体验：只留痕迹，不给能力分。
  experience('体验', '只记频次与主观分，不算能力值');

  const AxisKind(this.label, this.semantics);

  final String label;
  final String semantics;

  static AxisKind parseOrDefault(String? raw) {
    if (raw == 'experience') return experience;
    return ability;
  }
}

/// 一个维度的身份。`key` 是永远不改的机器码（内置用枚举名，用户维度用 `ua_*`）。
class AxisSpec {
  const AxisSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.decayTauDays = 0,
    this.builtin = false,
    this.decayCitation = '',
  });

  final String key;
  final String label;
  final AxisKind kind;

  /// 去训练时间常数（天）。`experience` 维度恒 0：它没有"能力"可掉。
  final double decayTauDays;

  final bool builtin;

  /// 为什么是这个衰减速度。`ability` 维度的必填项，`experience` 恒空。
  final String decayCitation;

  bool get isAbility => kind == AxisKind.ability;

  Map<String, Object?> toJson() => <String, Object?>{
        'axis_key': key,
        'label': label,
        'dim_kind': kind.name,
        if (isAbility) 'decay_tau_days': decayTauDays,
        if (decayCitation.isNotEmpty) 'decay_citation': decayCitation,
      };

  static AxisSpec fromJson(Map<String, Object?> json) => AxisSpec(
        key: json['axis_key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        kind: AxisKind.parseOrDefault(json['dim_kind']?.toString()),
        decayTauDays: (json['decay_tau_days'] as num?)?.toDouble() ?? 0,
        decayCitation: json['decay_citation']?.toString() ?? '',
      );
}

/// 注册表。**不可变**：加维度走 `withUserAxes`，返回新实例。
///
/// 不做成全局单例，是为了让测试能凭空构造一个干净的注册表，
/// 也让「内置 + 用户」的组合在调用点一眼看清。
class AxisRegistry {
  const AxisRegistry([this.userAxes = const <AxisSpec>[]]);

  final List<AxisSpec> userAxes;

  /// 内置 5 维。key 与 [ProjectAxis.name] 一一对应，**不许改名**：
  /// 库里 `axis` 列存的就是这些字符串，改名等于丢历史。
  static const List<AxisSpec> builtin = <AxisSpec>[
    AxisSpec(
      key: 'strength',
      label: '体能',
      kind: AxisKind.ability,
      decayTauDays: 21,
      builtin: true,
      decayCitation: '去训练效应经验近似（力量型 3 周起明显回落）',
    ),
    AxisSpec(
      key: 'cardio',
      label: '心肺',
      kind: AxisKind.ability,
      decayTauDays: 12,
      builtin: true,
      decayCitation: '去训练效应经验近似（心肺掉得比力量快）',
    ),
    AxisSpec(
      key: 'memory',
      label: '词汇',
      kind: AxisKind.ability,
      decayTauDays: 30,
      builtin: true,
      decayCitation: '遗忘曲线 + 复习间隔的经验近似',
    ),
    AxisSpec(
      key: 'writing',
      label: '写作',
      kind: AxisKind.ability,
      decayTauDays: 45,
      builtin: true,
      decayCitation: '去训练效应经验近似（技能型衰退慢）',
    ),
    AxisSpec(
      key: 'discipline',
      label: '自律',
      kind: AxisKind.ability,
      decayTauDays: 14,
      builtin: true,
      decayCitation: '行为习惯强度的经验近似',
    ),
  ];

  /// 未知轴的落点。**不许回退成 strength**（那是现存 bug 的做法：
  /// 会把「陪伴」静默记进体能，而且界面上看不出错）。
  static const AxisSpec unknown = AxisSpec(
    key: 'unknown',
    label: '未归类',
    kind: AxisKind.experience,
  );

  List<AxisSpec> get all => <AxisSpec>[...builtin, ...userAxes];

  List<AxisSpec> get abilityAxes =>
      all.where((AxisSpec a) => a.isAbility).toList(growable: false);

  List<AxisSpec> get experienceAxes =>
      all.where((AxisSpec a) => !a.isAbility).toList(growable: false);

  bool isBuiltinKey(String key) =>
      builtin.any((AxisSpec a) => a.key == key);

  /// 精确查。查不到返回 null —— 调用方必须自己决定怎么处理，
  /// 不能被一个"兜底值"骗过去。
  AxisSpec? tryResolve(String key) {
    for (final AxisSpec a in all) {
      if (a.key == key) return a;
    }
    return null;
  }

  AxisSpec resolve(String key) => tryResolve(key) ?? unknown;

  /// 去训练时间常数。未知维度按 30 天（与词汇同档），并保持 `experience` 为 0。
  double tauFor(String key) {
    // `unknown` 是体验维度，没有能力可掉——不许跟着"未知按 30 天"一起算。
    if (key == unknown.key) return 0;
    final AxisSpec? spec = tryResolve(key);
    if (spec == null) return 30;
    return spec.isAbility ? spec.decayTauDays : 0;
  }

  /// 系数键。内置维度映射到 `BalanceConfig.weightXxx`；
  /// 用户维度映射到 `axisWeight.<key>`（v1.2.1 在 `ConfigRepository` 白名单放行）。
  String weightConfigKey(String key) {
    if (key == 'strength') return 'weightStrength';
    if (key == 'cardio') return 'weightCardio';
    if (key == 'memory') return 'weightMemory';
    if (key == 'writing') return 'weightWriting';
    if (key == 'discipline') return 'weightRestraint';
    return 'axisWeight.$key';
  }

  AxisRegistry withUserAxes(List<AxisSpec> axes) => AxisRegistry(
        <AxisSpec>[
          ...userAxes,
          ...axes.where((AxisSpec a) => !_hasKey(a.key)),
        ],
      );

  bool _hasKey(String key) => all.any((AxisSpec a) => a.key == key);

  /// 生成一个不与现有维度冲突的 key。
  static String newAxisKey([DateTime? at]) =>
      'ua_${(at ?? DateTime.now()).millisecondsSinceEpoch}';

  /// 内置维度 key 与 [ProjectAxis] 必须一一对应（有测试守着）。
  static List<String> get builtinKeys =>
      builtin.map((AxisSpec a) => a.key).toList(growable: false);

  static List<String> get projectAxisNames =>
      ProjectAxis.values.map((ProjectAxis a) => a.name).toList(growable: false);
}
