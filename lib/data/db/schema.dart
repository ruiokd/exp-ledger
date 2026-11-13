/// 数据库结构：全部 DDL 的唯一来源。
///
/// 铁律：任何地方不要在别处再写一遍表名或建表语句。
/// 迁移、测试、导出、诊断都从这里取。
///
/// 表分三类：
///   1. 业务表（14 张，见 STATE.md 清单）
///   2. 结算产物表（day_settlement：一天的结算结果，级联重算的中间层）
///   3. 内部表（daily_log_history / dirty_day：修订链与脏日队列）
library;

/// 表名常量。字符串拼错在运行时才炸，所以统一走这里。
class Tables {
  const Tables._();

  // ---- 业务表 ----
  static const String userProfile = 'user_profile';
  static const String calibrationRecord = 'calibration_record';
  static const String captureSession = 'capture_session';
  static const String dailyLog = 'daily_log';
  static const String valenceEvent = 'valence_event';
  static const String negativeEvent = 'negative_event';
  static const String energyLedger = 'energy_ledger';
  static const String loadIndex = 'load_index';
  static const String abilitySnapshot = 'ability_snapshot';
  static const String forecastPoint = 'forecast_point';
  static const String memoryItem = 'memory_item';
  static const String confirmationTask = 'confirmation_task';
  static const String badge = 'badge';
  static const String configOverride = 'config_override';

  /// 应用设置（提醒开关/时间等）。和第 4 步的表不同：
  /// 这里存的是**用户偏好**，不参与结算，也不进导出以外的算法路径。
  static const String appSetting = 'app_setting';

  // ---- 结算产物 ----
  static const String daySettlement = 'day_settlement';

  // ---- 刻度标定层（第 8 步）----
  // 这四张表是后加的插件：它们只存"用户怎么量""估多重""实测多重"，
  // 不参与任何既有结算路径（preflight 4d 守着这条）。
  static const String userAnchor = 'user_anchor';
  static const String anchorRevision = 'anchor_revision';
  static const String declaredImpact = 'declared_impact';
  static const String anchorEvidence = 'anchor_evidence';

  /// 用户自建的项目（内置行为库之外的那些，「上一堂课」之类）。
  static const String customBehavior = 'custom_behavior';

  // ---- 量化形状层（v1.2.0）----
  // 与刻度层同一类插件：只存「这条行为怎么量」「有哪些自定义维度」，
  // 不参与结算。preflight 4e 守着"结算层不许 import quant"。
  static const String behaviorQuantSpec = 'behavior_quant_spec';
  static const String axisDefinition = 'axis_definition';

  // ---- 内部表 ----
  static const String dailyLogHistory = 'daily_log_history';
  static const String dirtyDay = 'dirty_day';

  /// 需要被「清空全部数据」遍历的表（顺序无关，因为无外键约束）。
  static const List<String> all = <String>[
    userProfile,
    calibrationRecord,
    captureSession,
    dailyLog,
    dailyLogHistory,
    valenceEvent,
    negativeEvent,
    energyLedger,
    loadIndex,
    daySettlement,
    abilitySnapshot,
    forecastPoint,
    memoryItem,
    confirmationTask,
    badge,
    configOverride,
    appSetting,
    dirtyDay,
    userAnchor,
    anchorRevision,
    declaredImpact,
    anchorEvidence,
    customBehavior,
    behaviorQuantSpec,
    axisDefinition,
  ];
}

/// 索引名常量。测试会按名字断言它们存在。
class Indexes {
  const Indexes._();

  static const String dailyLogIdempotency = 'ux_daily_log_idem';
  static const String dailyLogDay = 'ix_daily_log_day';
  static const String dailyLogBehavior = 'ix_daily_log_behavior';
  static const String historyKey = 'ix_history_key';

  static const String valenceSlot = 'ux_valence_slot';
  static const String valenceDay = 'ix_valence_day';

  static const String negativePrimary = 'ux_negative_primary';
  static const String negativeDay = 'ix_negative_day';

  static const String forecastDay = 'ix_forecast_day';

  static const String memoryDue = 'ix_memory_due';
  static const String confirmationDue = 'ix_confirmation_due';
  static const String calibrationTime = 'ix_calibration_time';
  static const String sessionDay = 'ix_session_day';

  // 刻度标定层
  static const String anchorRevisionTime = 'ix_anchor_revision_time';
  static const String anchorEvidenceBehavior = 'ix_anchor_evidence_behavior';
  static const String customBehaviorEnabled = 'ix_custom_behavior_enabled';

  // 量化形状层
  static const String axisDefinitionKind = 'ix_axis_definition_kind';
}

/// 自建项目的 DDL。
///
/// 为什么要 target_dose：EXP 由 `baseScoreFor(doseFraction)` 算，
/// 而 doseFraction = 实际量 / 目标量。内置行为把目标量写死在代码里，
/// 自建的只能存库——否则"上一堂课 45 分钟"这种没有分母。
const List<String> kCustomBehaviorTables = <String>[
  '''
CREATE TABLE IF NOT EXISTS custom_behavior (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL,
  axis TEXT NOT NULL,
  measurement_class TEXT NOT NULL,
  unit_label TEXT NOT NULL,
  definition_text TEXT NOT NULL DEFAULT '',
  target_dose REAL NOT NULL DEFAULT 1,
  dose_unit TEXT NOT NULL DEFAULT '次',
  tier TEXT NOT NULL DEFAULT 'medium',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE INDEX IF NOT EXISTS ix_custom_behavior_enabled
  ON custom_behavior (enabled, updated_at DESC)
''',
];

/// 量化形状层的 DDL（两张表 + 一个索引）。
///
/// 为什么是两张新表而不是给 `custom_behavior` 加列：
///   1. `custom_behavior` 是 v4 已发布的表，加列要做 ALTER；这条链上已经
///      因为"顺手改一下"炸过一次启动（六之六），能不加就不加。
///   2. 「怎么量」和「这是什么行为」生命周期不同：行为可以改名、改单位，
///      而量化口径改一次就要留下痕迹（[revision]），两者混在一行里没法回看。
///
/// `CHECK` 是硬约束，不是文档：
///   - `target_dose > 0`：分母为 0 的折算在任何层都没有意义；
///   - `shape_kind` 四选一：白名单之外的形状必须由代码打回，不能靠调用方自觉；
///   - `dim_kind` 两选一，且 `ability` 必须有衰减常数（说不出"为什么掉这么慢"
///     就不配进能力曲线——这条在 domain 里也判一次，这里再兜一次）。
const List<String> kQuantTables = <String>[
  '''
CREATE TABLE IF NOT EXISTS behavior_quant_spec (
  behavior_code TEXT PRIMARY KEY,
  measure_kind TEXT NOT NULL,
  measure_unit TEXT NOT NULL,
  how_to_check TEXT NOT NULL DEFAULT '',
  shape_kind TEXT NOT NULL DEFAULT 'linear'
    CHECK (shape_kind IN ('linear', 'log', 'saturating', 'threshold')),
  shape_k REAL,
  shape_theta_fraction REAL,
  target_dose REAL NOT NULL CHECK (target_dose > 0),
  impact_json TEXT NOT NULL DEFAULT '[]',
  citation TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'userPrior',
  note TEXT NOT NULL DEFAULT '',
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS axis_definition (
  axis_key TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  dim_kind TEXT NOT NULL DEFAULT 'experience'
    CHECK (dim_kind IN ('ability', 'experience')),
  decay_tau_days REAL NOT NULL DEFAULT 0
    CHECK (dim_kind <> 'ability' OR decay_tau_days > 0),
  decay_citation TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE INDEX IF NOT EXISTS ix_axis_definition_kind
  ON axis_definition (dim_kind, enabled)
''',
];

/// 刻度标定层的 DDL（四张表 + 两个索引）。
///
/// 抽成常量是因为它要在两处用到：全新建库（[kCreateStatements] 里展开）
/// 和 v2 → v3 迁移。两处各抄一遍 SQL 迟早漂移（`app_setting` 的教训）。
///
/// 设计要点：
///   - `user_anchor` / `declared_impact` 的主键都是 `behavior_id`：
///     一个行为只有一张刻度卡片，天然幂等（重复保存只覆盖）。
///   - 证据只追加（`anchor_evidence` 无更新路径），先验的 `replaced_by`
///     指向证据 id——「当初估的是中偏大、实测接近中」这句话要可回溯。
///   - 刻度变更进 `anchor_revision`，图表在这些时间点画竖线；
///     历史记录不重算（哪天的记录用哪天的刻度，由 `AnchorEngine` 判定）。
const List<String> kAnchorTables = <String>[
  '''
CREATE TABLE IF NOT EXISTS user_anchor (
  behavior_id TEXT PRIMARY KEY,
  unit_label TEXT NOT NULL,
  definition_text TEXT NOT NULL DEFAULT '',
  reference_object TEXT NOT NULL DEFAULT '',
  measurement_class TEXT NOT NULL,
  reference_range_id TEXT NOT NULL DEFAULT 'custom',
  calibrated_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS anchor_revision (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  behavior_id TEXT NOT NULL,
  field TEXT NOT NULL,
  from_value TEXT NOT NULL DEFAULT '',
  to_value TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT '',
  changed_at TEXT NOT NULL
)
''',
  '''
CREATE INDEX IF NOT EXISTS ix_anchor_revision_time
  ON anchor_revision (behavior_id, changed_at DESC)
''',
  '''
CREATE TABLE IF NOT EXISTS declared_impact (
  behavior_id TEXT PRIMARY KEY,
  tier TEXT NOT NULL,
  source TEXT NOT NULL,
  weight REAL NOT NULL,
  declared_at TEXT NOT NULL,
  replaced_by TEXT,
  note TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS anchor_evidence (
  id TEXT PRIMARY KEY,
  behavior_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  measured_value REAL NOT NULL,
  unit TEXT NOT NULL,
  derived_tier TEXT NOT NULL,
  performed_at TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  confidence TEXT NOT NULL DEFAULT 'calibrated',
  created_at TEXT NOT NULL
)
''',
  '''
CREATE INDEX IF NOT EXISTS ix_anchor_evidence_behavior
  ON anchor_evidence (behavior_id, performed_at DESC)
''',
];

/// `app_setting` 的建表语句。
///
/// 单独抽成常量，是因为它要在两个地方用到：全新建库（[kCreateStatements]）
/// 和 v1 → v2 迁移。两处各抄一遍 SQL 迟早会漂移。
const String kAppSettingTable = '''
CREATE TABLE IF NOT EXISTS app_setting (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

/// 建表 + 建索引语句。逐条执行（sqflite 的 execute 不支持多语句）。
const List<String> kCreateStatements = <String>[
  // ---------------------------------------------------------------- 用户档案
  '''
  CREATE TABLE IF NOT EXISTS user_profile (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    height_cm REAL NOT NULL DEFAULT 172,
    weight_kg REAL NOT NULL DEFAULT 70,
    age INTEGER NOT NULL DEFAULT 28,
    sex TEXT NOT NULL DEFAULT 'male',
    resting_hr INTEGER NOT NULL DEFAULT 66,
    body_fat REAL,
    sleep_need_hours REAL NOT NULL DEFAULT 7.5,
    sleep_line_hour INTEGER NOT NULL DEFAULT 0,
    sleep_line_minute INTEGER NOT NULL DEFAULT 20,
    vocabulary_estimate INTEGER NOT NULL DEFAULT 6000,
    one_rm_squat REAL,
    vo2max_estimate REAL,
    profile_confidence TEXT NOT NULL DEFAULT 'selfReport',
    sleep_confidence TEXT NOT NULL DEFAULT 'selfReport',
    vo2_confidence TEXT NOT NULL DEFAULT 'selfReport',
    vocab_confidence TEXT NOT NULL DEFAULT 'selfReport',
    last_calibrated_at TEXT,
    updated_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 校准记录
  '''
  CREATE TABLE IF NOT EXISTS calibration_record (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    axis TEXT NOT NULL,
    measured_value REAL NOT NULL,
    unit TEXT NOT NULL,
    source TEXT NOT NULL,
    confidence_before TEXT NOT NULL,
    confidence_after TEXT NOT NULL,
    raw_json TEXT NOT NULL DEFAULT '{}',
    performed_at TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_calibration_time
    ON calibration_record (performed_at DESC)
  ''',

  // ---------------------------------------------------------------- 采集会话
  '''
  CREATE TABLE IF NOT EXISTS capture_session (
    id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    day_key TEXT,
    behavior_code TEXT,
    raw_text TEXT,
    stage TEXT NOT NULL DEFAULT 'intent',
    answered_count INTEGER NOT NULL DEFAULT 0,
    abandoned INTEGER NOT NULL DEFAULT 0,
    used_same_as_last INTEGER NOT NULL DEFAULT 0,
    used_voice INTEGER NOT NULL DEFAULT 0,
    confidence_ceiling TEXT NOT NULL DEFAULT 'calibrated',
    entry_source TEXT NOT NULL DEFAULT 'manual',
    trace_json TEXT NOT NULL DEFAULT '[]'
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_session_day
    ON capture_session (day_key, started_at DESC)
  ''',

  // ---------------------------------------------------------------- 原始记录
  '''
  CREATE TABLE IF NOT EXISTS daily_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day_key TEXT NOT NULL,
    behavior_code TEXT NOT NULL,
    category TEXT NOT NULL,
    valence TEXT NOT NULL,
    axis TEXT NOT NULL,
    plan_status TEXT NOT NULL,
    confidence TEXT NOT NULL,
    slot_key TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    answers_json TEXT NOT NULL DEFAULT '{}',
    metrics_json TEXT NOT NULL DEFAULT '{}',
    interpretation TEXT NOT NULL DEFAULT '',
    dose_fraction REAL NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'manual',
    created_at TEXT NOT NULL,
    session_id TEXT,
    notes_json TEXT NOT NULL DEFAULT '[]',
    warnings_json TEXT NOT NULL DEFAULT '[]',
    revision INTEGER NOT NULL DEFAULT 0,
    is_interruption INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ux_daily_log_idem
    ON daily_log (idempotency_key)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_daily_log_day
    ON daily_log (day_key, behavior_code)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_daily_log_behavior
    ON daily_log (behavior_code, day_key DESC)
  ''',

  // 修订链：被覆盖的旧版本留在这里，永远不删（除了「清空全部数据」）。
  '''
  CREATE TABLE IF NOT EXISTS daily_log_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    idempotency_key TEXT NOT NULL,
    revision INTEGER NOT NULL,
    day_key TEXT NOT NULL,
    row_json TEXT NOT NULL,
    superseded_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ix_history_key
    ON daily_log_history (idempotency_key, revision)
  ''',

  // ---------------------------------------------------------------- 正向事件
  '''
  CREATE TABLE IF NOT EXISTS valence_event (
    id TEXT PRIMARY KEY,
    day_key TEXT NOT NULL,
    behavior_code TEXT NOT NULL,
    behavior_name TEXT NOT NULL,
    slot_key TEXT NOT NULL DEFAULT '',
    valence TEXT NOT NULL,
    axis TEXT NOT NULL,
    base_score REAL NOT NULL DEFAULT 0,
    quality_bonus REAL NOT NULL DEFAULT 0,
    efficiency_bonus REAL NOT NULL DEFAULT 0,
    normalized_score REAL NOT NULL DEFAULT 0,
    weight REAL NOT NULL DEFAULT 1,
    state_multiplier REAL NOT NULL DEFAULT 1,
    confidence_weight REAL NOT NULL DEFAULT 1,
    exp REAL NOT NULL DEFAULT 0,
    confidence TEXT NOT NULL DEFAULT 'selfReport',
    notes_json TEXT NOT NULL DEFAULT '[]',
    breakdown_json TEXT NOT NULL DEFAULT '{}',
    estimated INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ux_valence_slot
    ON valence_event (day_key, behavior_code, slot_key)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_valence_day
    ON valence_event (day_key)
  ''',

  // ---------------------------------------------------------------- 负向事件
  '''
  CREATE TABLE IF NOT EXISTS negative_event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day_key TEXT NOT NULL,
    behavior_code TEXT NOT NULL,
    behavior_name TEXT NOT NULL,
    dose_minutes REAL NOT NULL DEFAULT 0,
    penalty_units REAL NOT NULL DEFAULT 0,
    exp REAL NOT NULL DEFAULT 0,
    root_cause_key TEXT NOT NULL,
    is_primary INTEGER NOT NULL DEFAULT 1,
    suppressed_by TEXT,
    consequences_json TEXT NOT NULL DEFAULT '[]',
    recovery_hints_json TEXT NOT NULL DEFAULT '[]',
    notes_json TEXT NOT NULL DEFAULT '[]'
  )
  ''',
  // 部分唯一索引：只约束「主因」。同根因的后果记录（exp = 0）可以有多条。
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ux_negative_primary
    ON negative_event (day_key, root_cause_key)
    WHERE is_primary = 1
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_negative_day
    ON negative_event (day_key, root_cause_key)
  ''',

  // ---------------------------------------------------------------- 能量账本
  '''
  CREATE TABLE IF NOT EXISTS energy_ledger (
    day_key TEXT PRIMARY KEY,
    intake_kcal REAL NOT NULL DEFAULT 0,
    bmr REAL NOT NULL DEFAULT 0,
    tef REAL NOT NULL DEFAULT 0,
    exercise REAL NOT NULL DEFAULT 0,
    epoc REAL NOT NULL DEFAULT 0,
    neat REAL NOT NULL DEFAULT 0,
    expenditure REAL NOT NULL DEFAULT 0,
    training_efficiency REAL NOT NULL DEFAULT 0,
    time_efficiency REAL NOT NULL DEFAULT 0,
    balance_low REAL NOT NULL DEFAULT 0,
    balance_high REAL NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 负荷索引
  '''
  CREATE TABLE IF NOT EXISTS load_index (
    day_key TEXT PRIMARY KEY,
    srpe_today REAL NOT NULL DEFAULT 0,
    acute_7 REAL NOT NULL DEFAULT 0,
    chronic_28 REAL NOT NULL DEFAULT 0,
    acwr REAL,
    band TEXT NOT NULL DEFAULT 'low',
    damage_load REAL NOT NULL DEFAULT 0,
    sleep_debt_hours REAL NOT NULL DEFAULT 0,
    consecutive_high_days INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 当日结算
  '''
  CREATE TABLE IF NOT EXISTS day_settlement (
    day_key TEXT PRIMARY KEY,
    positive_exp REAL NOT NULL DEFAULT 0,
    negative_exp REAL NOT NULL DEFAULT 0,
    net_exp REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'settled',
    state_before_json TEXT NOT NULL DEFAULT '{}',
    state_after_json TEXT NOT NULL DEFAULT '{}',
    alert_json TEXT,
    notes_json TEXT NOT NULL DEFAULT '[]',
    recovery_json TEXT NOT NULL DEFAULT '[]',
    level_before INTEGER NOT NULL DEFAULT 0,
    level_after INTEGER NOT NULL DEFAULT 0,
    buffer_after REAL NOT NULL DEFAULT 0,
    is_interruption INTEGER NOT NULL DEFAULT 0,
    revision INTEGER NOT NULL DEFAULT 0,
    computed_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 能力快照
  '''
  CREATE TABLE IF NOT EXISTS ability_snapshot (
    day_key TEXT PRIMARY KEY,
    abilities_json TEXT NOT NULL DEFAULT '{}',
    completeness_json TEXT NOT NULL DEFAULT '{}',
    total_exp REAL NOT NULL DEFAULT 0,
    level INTEGER NOT NULL DEFAULT 0,
    buffer REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'settled',
    computed_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 预测点
  '''
  CREATE TABLE IF NOT EXISTS forecast_point (
    day_key TEXT NOT NULL,
    axis TEXT NOT NULL,
    horizon_days INTEGER NOT NULL DEFAULT 0,
    maintain REAL NOT NULL DEFAULT 0,
    correct REAL NOT NULL DEFAULT 0,
    low REAL NOT NULL DEFAULT 0,
    high REAL NOT NULL DEFAULT 0,
    confidence REAL NOT NULL DEFAULT 1,
    is_projection INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day_key, axis, horizon_days)
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_forecast_day
    ON forecast_point (day_key, axis)
  ''',

  // ---------------------------------------------------------------- 记忆条目
  '''
  CREATE TABLE IF NOT EXISTS memory_item (
    id TEXT PRIMARY KEY,
    word TEXT NOT NULL,
    axis TEXT NOT NULL DEFAULT 'memory',
    strength REAL NOT NULL DEFAULT 1,
    coverage REAL NOT NULL DEFAULT 0,
    review_count INTEGER NOT NULL DEFAULT 0,
    active_recall INTEGER NOT NULL DEFAULT 1,
    last_review_at TEXT,
    next_review_at TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_memory_due
    ON memory_item (next_review_at)
  ''',

  // ---------------------------------------------------------------- 确认任务
  '''
  CREATE TABLE IF NOT EXISTS confirmation_task (
    id TEXT PRIMARY KEY,
    day_key TEXT,
    behavior_code TEXT,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open',
    payload_json TEXT NOT NULL DEFAULT '{}',
    due_at TEXT,
    created_at TEXT NOT NULL,
    resolved_at TEXT
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS ix_confirmation_due
    ON confirmation_task (status, due_at)
  ''',

  // ---------------------------------------------------------------- 徽章
  '''
  CREATE TABLE IF NOT EXISTS badge (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL,
    title TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    day_key TEXT,
    earned_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 配置覆盖
  '''
  CREATE TABLE IF NOT EXISTS config_override (
    key TEXT PRIMARY KEY,
    value REAL NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 应用设置
  kAppSettingTable,

  // ---------------------------------------------------------------- 脏日队列
  // 写入后只标 day_key，重算时从「最早的脏日」一路跑到今天。
  // 这张表让「历史修正」跨进程也有效：进程被杀不会丢重算任务。
  '''
  CREATE TABLE IF NOT EXISTS dirty_day (
    day_key TEXT PRIMARY KEY,
    reason TEXT NOT NULL DEFAULT 'write',
    marked_at TEXT NOT NULL
  )
  ''',

  // ---------------------------------------------------------------- 刻度标定层
  // 第 8 步新增。只追加，不动上面任何一句 DDL。
  ...kAnchorTables,

  // ---------------------------------------------------------------- 自建项目
  // 第 11 步新增：内置库之外的行为。**只是"行为本身"**——
  // 单位、档位仍住在 user_anchor / declared_impact（一个行为一套刻度），
  // 这里存的是画卡片和生成提问要用的快照。
  ...kCustomBehaviorTables,

  // ---------------------------------------------------------------- 量化形状层
  // v1.2.0 新增：怎么量 + 自定义维度。只追加，不动上面任何一句 DDL，
  // 17 张老表一条没改（`tools/schema_check.py` 会逐表数一遍列）。
  ...kQuantTables,
];
