/// 全局枚举。放在 domain 顶层，任何层都可以 import，且不依赖 Flutter。

/// 行为的情感价（valence）：决定进入加分还是扣分通道。
enum Valence {
  positive,
  negative,
  neutral,

  /// 计划外事件：本身不带价，需先判定"有益超额 / 过量风险 / 中断期"。
  offPlan,
}

/// 行为的三大类，用于行为库分区与 UI 配色。
enum BehaviorCategory {
  positive,
  negative,
  offPlan;

  String get label => switch (this) {
        BehaviorCategory.positive => '正向',
        BehaviorCategory.negative => '负向',
        BehaviorCategory.offPlan => '计划外',
      };
}

/// 数据可信度。权重用于 EXP 折价，绝不因为自报就淘汰用户。
enum Confidence {
  /// 用户直接填报，无实测支撑。
  selfReport,

  /// 由公式从其他字段推算得出。
  formula,

  /// 经标准化校准测试或现实确认闭环反推得出。
  calibrated;

  double get weight => switch (this) {
        Confidence.selfReport => 0.6,
        Confidence.formula => 0.8,
        Confidence.calibrated => 1.0,
      };

  /// 回执里的说法：不用"低/高"评价用户，只说明来源。
  String get receiptLabel => switch (this) {
        Confidence.selfReport => '中（自报）',
        Confidence.formula => '中（公式推算）',
        Confidence.calibrated => '高（实测校准）',
      };

  /// 徽章上的短标记。
  String get badgeLabel => switch (this) {
        Confidence.selfReport => '自报',
        Confidence.formula => '推算',
        Confidence.calibrated => '校准',
      };

  static Confidence parse(String raw) =>
      Confidence.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => Confidence.selfReport,
      );

  /// 取两者中较低者——合成数据总是被最弱环节拖累。
  static Confidence min(Confidence a, Confidence b) =>
      a.index <= b.index ? a : b;
}

/// 该行为是否在原计划内。决定走超额通道还是缺席/中断通道。
enum PlanStatus {
  planned,
  offPlan,
  missed;

  String get label => switch (this) {
        PlanStatus.planned => '按计划',
        PlanStatus.offPlan => '临时加的',
        PlanStatus.missed => '计划里有但没做',
      };

  static PlanStatus parse(String raw) =>
      PlanStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => PlanStatus.planned,
      );
}

/// 当日结算状态。安全兜底触发时暂停，不算分也不扣分。
enum SettlementStatus {
  settled,
  paused,
  frozen;

  String get label => switch (this) {
        SettlementStatus.settled => '已结算',
        SettlementStatus.paused => '暂停结算（安全提示）',
        SettlementStatus.frozen => '中断期',
      };
}

/// 问题控件的形态。按钮化优先，键盘永远是最末选项。
enum QuestionKind {
  /// 单选 chip。
  choice,

  /// 数字步进器。
  number,

  /// 时间点（入睡/醒来）。
  timeOfDay,

  /// 时长（分钟/小时）。
  duration,
}

/// 采集会话当前所处阶段，用于埋点式本地诊断与 UI 顶部进度。
enum CaptureStage {
  idle,
  intent,
  disambiguating,
  planGate,
  questioning,
  receipting,
  committed,
  freeform,
  aborted,
}

/// 单位标识，落库时随指标一起保存，避免"12"不知道是次还是组。
enum MeasureUnit {
  rep,
  set,
  kilogram,
  minute,
  hour,
  word,
  count,
  serving,
  kcal,
  percent;

  String get symbol => switch (this) {
        MeasureUnit.rep => '次',
        MeasureUnit.set => '组',
        MeasureUnit.kilogram => 'kg',
        MeasureUnit.minute => '分钟',
        MeasureUnit.hour => '小时',
        MeasureUnit.word => '词',
        MeasureUnit.count => '次',
        MeasureUnit.serving => '份',
        MeasureUnit.kcal => 'kcal',
        MeasureUnit.percent => '%',
      };
}
