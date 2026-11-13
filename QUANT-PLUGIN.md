# 量化形状与自建维度（Quant Layer）· 设计说明与边界

> 这一层要解决的是三件被混在一起的事：
>
> 1. 自建项目现在只会算 `实际量 / 目标量`（线性），「一次看电影」和「一次刷题」用同一条直线；
> 2. 所有项目都被塞进 5 个内置维度之一，一个「陪伴」被迫记成 `discipline`；
> 3. AI 只被允许说「这事多重大」（档位），不许说「这事怎么量」。
>
> 结论：**三件事都能做，但要分别给它们不同的容器**，混在一个数值里必然自欺。
> 本轮只落设计 + 第一刀（量化形状），维度扩展与体验曲线排在其后。

---

## 一、判定：能，但"新曲线"有三种，不能合并

| 曲线 | 纵轴是什么 | 可不可验证 | 谁能进 |
|---|---|---|---|
| **能力曲线**（现有主图） | 练出来的存量（0–120），有衰减 | 可（剂量→EXP→存量是封闭算式） | 有可核对单位的维度 |
| **体验曲线**（新增） | 每周频次 + 主观分均值与误差带 | 半可（主观分是自报，但频次是事实） | 纯体验维度（关系、情绪、审美） |
| **先验刻度曲线**（第 8 步已有） | 这件事多重（≤0.5 权重，空心点） | 不可，等实测覆盖 | 所有项目 |

**关键约束：一次亲吻不该让「体能」涨 0.3 分。**
把它塞进能力曲线，是因为"总得有个维度放"，不是因为算得出来。
所以新维度必须带 `dim_kind`：

- `ability` —— 进主曲线，必须有衰减常数依据（内置 5 维是经验近似；用户新增的必须给 citation，否则不许建）；
- `experience` —— 进体验曲线，**EXP 权重恒 0**，不给能力值，只记频次与主观分。

这与已有的 `MeasurementClass.subjective`（EXP 权重 0）是同一条纪律的延伸，不是新规矩。

---

## 二、量化形状：只有四种，且都归一化到「目标量 = 满分线」

### 为什么不能让 AI 自由写公式

AI 说「这件事的收益是 `x^0.3·log(1+x)`」——不可验证、不可复算、不可比较。
让它选形状、填参数、给依据，参数只能来自两处：用户定的 `target_dose`，
或带出处的参照区间。这样每一分都能被追问到底。

### 四种形状（首批），统一写成 `s(d)/s(T)`，保证 `s(T) = 1`

设目标量 `T`，本次量 `d`：

```
linear      x = d / T                                   （现行为，默认）
log         x = ln(1 + k·d/T) / ln(1 + k)               k ∈ {0.5, 1, 2, 4}
saturating  x = [d/(d+K)] / [T/(T+K)]                   K = T/3
threshold   x = 0 (d < θ) / 1 (d ≥ θ)                   θ ∈ {T, 0.5T}
```

归一化的意义：**目标量处永远是 1.0**，所以 `baseScoreFor`、质量加成、效率加成、
状态乘数、置信权重一个字都不用改。形状只改「没做满时怎么算」这一段。

更重要的第二层约束：**形状必须尺度不变**。对数那一支里 `k` 必须无量纲、作用在
`d/T` 上；写成 `ln(1+k·d)/ln(1+k·T)` 在 `d = T` 处也等于 1，但目标量 40 时做一半得
0.82、目标量 1 时得 0.585——用户改一下目标量就悄悄改了形状，界面上还看不出来。
这个坑在实现时踩过一次，测试里有一条专门守它（同一比例、三种量级，结果必须相同）。

数值对照（T=1）：

| d | linear | log k=1 | saturating | threshold |
|---|---|---|---|---|
| 0.25T | 0.250 | 0.322 | 0.571 | 0 |
| 0.50T | 0.500 | 0.585 | 0.800 | 0 |
| 1.00T | 1.000 | 1.000 | 1.000 | 1 |
| 1.50T | 1.500 | 1.322 | 1.091 | 1 |

同一件事做一半，`baseScoreFor`（指数 0.8）给出 57 / 65 / 84 / 0 分。
这就是「形状」这一层真正值钱的地方，且它完全在既有公式内部。

### 什么时候用哪个（给 AI 的判定口径）

| 形状 | 语义 | 例子 |
|---|---|---|
| `linear` | 做得越多越好，线性累积到目标 | 背单词、俯卧撑组数 |
| `log` | 前段有效、后段边际递减 | 阅读、写作、练习曲 |
| `saturating` | 有生理/时间上限，超出几乎不加 | 陪伴、冥想、拉伸 |
| `threshold` | 要么发生要么没发生，不存在"做一半" | 看一场电影、一次约会、一次体检 |

`biphasic`（好事过头反噬）**本轮不做**：负向已由独立 `category` + `negativeCurve`
承担，一个形状同时产出正负会破坏「负向不乘状态乘数」这条铁律。
观察半年，确有需要再单开一版。

### 参数纪律（写进校验器，不靠自觉）

- `k` 只接受 `{0.5, 1, 2, 4}` 四档，其余值整条打回（`R_FREE_PARAM`）；
- `θ` 只接受 `T` 或 `0.5T`，不接受绝对值（否则改目标量时阈值不跟着走）；
- `target_dose > 0` 必填（沿用 v1.1.3 的规矩）；
- `shape` 缺失 = `linear`（向后兼容 DB 里已有的自建项目，一个也不用迁）。

---

## 三、AI 协议扩展：从「一档」到「一档 + 一个形状 + 一组维度」

现有 `NewBehaviorCodec` 的条目扩两个字段（旧回复仍可解析，缺省即 linear / 单维度）：

```json
{
  "name": "看一场电影",
  "tier": "medium",
  "unit_label": "一次电影",
  "definition_text": "从片头到片尾，中途不刷手机",
  "target_dose": 1,
  "dose_unit": "次",
  "quant": {
    "measure": { "kind": "episode", "unit": "次", "how_to_check": "看没看完片尾字幕" },
    "shape": { "kind": "threshold", "theta": "T", "citation": "—（事件型，无剂量响应）" },
    "impact": [
      { "axis": "relation", "axis_label": "关系", "dim_kind": "experience", "share": 1.0 }
    ]
  },
  "rationale": "看电影是事件而非剂量，半个电影不成立",
  "citation": "事件型行为按发生/未发生二值计，不适用剂量-反应曲线"
}
```

### 新增四道闸（与既有四道并列，行为一致：打回或降档，不中断整批）

| 闸 | 触发 | 行为 | 原因码 |
|---|---|---|---|
| 形状白名单 | `shape.kind` 不在四种内 | 整条打回 | `R_UNKNOWN_SHAPE` |
| 自由参数 | `k` / 绝对 θ / 自造参数 | 整条打回 | `R_FREE_PARAM` |
| 维度份额 | `Σshare ≠ 1 ± 0.01` 或 `share ≤ 0` | 归一化并提示，不静默 | `T_SHARE_RENORMALIZED` |
| 新维度无依据 | `dim_kind: ability` 但没有 `decay_citation` | 降级为 `experience` | `T_AXIS_DEMOTED` |

最后一条是这一层唯一不能被 AI 推翻的规则：**能力值必须能说出"为什么掉这么慢"**，
说不出就只配进体验曲线。

### 身份仍然是人的

AI 提议 → 用户逐条确认 → `source` 变 `userPrior`。
形状也一样：确认后是「用户的量化口径」，AI 的原话留在 `note` 里。

---

## 四、数据模型（v5，两张新表，零 ALTER，17 张老表一条不动）

```
behavior_quant_spec     这条行为怎么量（一行为一行，改口径 revision +1）
  behavior_code TEXT PRIMARY KEY
  measure_kind TEXT        durationMin | count | episode | rating（枚举名）
  measure_unit TEXT
  how_to_check TEXT        事后怎么判断这次算不算
  shape_kind    TEXT       CHECK IN (linear, log, saturating, threshold)
  shape_k        REAL      仅 log 用
  shape_theta_fraction REAL 仅 threshold 用（0.5 或 1）
  target_dose   REAL       CHECK > 0
  impact_json   TEXT       [{"axis":"relation","axis_label":"关系","dim_kind":"experience","share":1}]
  citation / source / note  TEXT
  revision      INTEGER    改一次 +1（改口径要留痕）
  created_at / updated_at TEXT

axis_definition          用户新增的维度（内置 5 维不落表）
  axis_key      TEXT PRIMARY KEY   'ua_<时间戳>'
  label         TEXT
  dim_kind      TEXT       CHECK IN (ability, experience)
  decay_tau_days REAL      CHECK: ability 时必须 > 0
  decay_citation TEXT
  enabled       INTEGER
  created_at / updated_at TEXT
```

**`default_weight` 这一列故意没有**：轴权重是系数，必须住在 `BalanceConfig`
（`axisWeight.<key>`，走 `configOverride` 覆盖）。放进表里就能绕过重算通道，
铁律 5 当场破。

两个必须知道的点：

1. **`ability_snapshot.abilities_json` 是 JSON map**，天然支持任意维度名，
   `forecast_point.axis` 是 TEXT，所以**新维度落库不需要任何 DDL 变更**。
   真正卡住的是代码里 8 处 `for (final axis in ProjectAxis.values)`。
2. **轴权重仍然是系数，不是数据**。用户轴权重进 `BalanceConfig.axisWeightOf(String)`，
   由 `configOverride` 覆盖，白名单在 `kDefaultConfig.toMap()` 的基础上放行
   `axisWeight.<axis_key>`。写进表里会让「改个权重」绕过重算通道，铁律 5 就破了。

### `ProjectAxis.parse` 的静默回退要修（现存 bug）

现在未知轴一律回退成 `strength`。一旦自建项目带自定义轴，这会把「陪伴」记进体能，
而且不报错、不提示、图上看着还挺对。改成：

```dart
static ProjectAxis? tryParse(String raw) => ...;  // 未知返回 null
```

调用点（6 个 DAO + snapshot）遇到 null 走 `unknown` 轴，且记一条 warn 日志。

---

## 五、要改的代码（精确到文件，按依赖顺序）

| # | 文件 | 改动 | 风险 | 状态 |
|---|---|---|---|---|
| 0 | `lib/domain/quant/`（8 文件） | 形状 / 量法 / 规格 / 四道闸 / 注册表 / 协议两端 / 出口 | 无（纯新增） | ✅ 已落 |
| 0b | `lib/domain/models/custom_behavior_def.dart` | 记录 → `BehaviorDef` 的适配器（模型文件不再 import quant） | 低 | ✅ 已落 |
| 0c | `lib/presentation/quant/shape_picker.dart` | 四选一控件（新建页 / 将来口径页共用） | 低 | ✅ 已落 |
| 0 | `test/quant/`（5 文件 / 92 个 test） | 数值断言 + 四道闸 + 括号配对 + 口径接线 | 无 | ✅ 已落，已进 CI |
| 1 | `lib/data/db/schema.dart` + `migrations.dart` | v4 → v5，两张新表（纯追加，0 行删除） | 低 | ✅ 已落 |
| 1b | `lib/data/dao/quant_dao.dart` + `repository/quant_repository.dart` | 行搬运 + 唯一写入口（四道闸在写之前） | 低 | ✅ 已落 |
| 2 | `lib/data/repository/custom_behavior_repository.dart` | `create` 事务里多写一条 linear 基线（四处同事务），`remove` 一起删 | 中 | ✅ 已落 |
| 3 | `lib/domain/models/custom_behavior.dart` | `derive` 里 `fraction = dose/target` → `spec.doseFractionFor(dose)`，加 `linearBaselineFor` | 中：**linear 的分数完全不变** | ✅ 已落 |
| 4 | `lib/domain/models/project_axis.dart` | 加 `tryParse`（未知返回 null）；`ProjectAxis` 保留为内置常量 | 中：波及 11 个文件 | 待做 |
| 5 | `lib/domain/forecast/decay_model.dart` | `detrainTau` 从 switch 改查注册表 | 中 | 待做 |
| 6 | `lib/data/snapshot/snapshot_builder.dart` | 3 处 `ProjectAxis.values` → 注册表全集 | **高**：改错会让主曲线少一条 | 待做 |
| 7 | `lib/presentation/chart/chart_page.dart` | N 维选择器；主图默认 ≤ 3 条 | 中 | 待做 |
| 8 | `lib/presentation/anchor/new_behavior_page.dart` | 第三步加「怎么折算」形状四选一（维度选择留到 v1.2.1） | 中 | ✅ 已落 |

第 3 步是分水岭：做完它，**量化方式就已经是 AI 给的了**，而维度扩展还没动。
这也是为什么它单独排一个可出包版本。

已经落地的部分（本轮）：v5 迁移 + 两张表 + DAO + `QuantRepository` +
自建项目创建时的 linear 基线。**基线那条与 v1.1.3 的行为逐字等价**
（那时 `derive` 里就是 `实际量 / 目标量`），所以现在装上的口径变了、分数一点没变；
下一步把 `derive` 改成读库里的口径，同样的记录仍得到同样的分。

### 已经落地的边界守卫（`tools/preflight.sh` 4e）

```
1. lib/domain/quant/ 不许 import flutter / sqflite / data / presentation / services
2. lib/domain/{engine,settlement,science,behaviors,capture,forecast} 不许 import quant
3. quant 层不许出现 expPerPoint / applyExp / totalExp / SettlementPipeline（不许算分）
4. quant 与 anchor 互不依赖
```

外加 **4f：公开 API 清单**（17 个声明必须都在）。理由很具体：
把 `quant_codec.dart` 切成 request/response 时，`buildQuantRequestText` 与
`QuantDecodeResult` 正好落在接缝上被切掉了，而 `parse_dart` 只查语法、
`check_symbols` 只查类型 import —— 两个工具都是绿的。只有测试编译会炸。
清单守卫让这种"沉默的丢失"在 preflight 阶段就红。

切割之后的 import 图（这是切割的目的，不是洁癖）：

```
custom_behavior.dart        纯记录，不 import quant
custom_behavior_def.dart    适配器 → import quant
app_shell / repository      读库里的口径，喂给适配器
```
"数据" 与 "适配器" 在 import 图上分开之后，"谁能让分数变"这个问题有一张图可查。

第 2 条允许的接线口只有 `lib/domain/models`：口径可以进"行为定义"，
但不许进"结算流水线"。四道闸全绿才允许出包。

---

## 六、与既有待办的插入顺序

现有 ①–⑤ 不动，这一层插在后面，拆三个可出包版本：

- **v1.2.0（= 上面的 1–6 步）**：形状层。AI 开始给「怎么量」；自建项目不再全是直线。
  红线检查：`baseScoreFor` 一行不改；旧自建项目走 `linear` 缺省，曲线不变。
- **v1.2.1（= 7–8 步）**：维度注册表 + 用户能力维度。主曲线仍只画内置 5 维，
  新维度可在「更多维度」里开。
- **v1.2.2（= 9–11 步）**：体验曲线（频次 + 主观带）+ 主图维度选择器 + 新建页接线。

不建议一次做完：第 9 步改的是主曲线的数据源，一旦错就是"图少一条线"这种最难自证的错误，
必须单独一版 + 装机对比截图。

---

## 七、不要做的四件事

1. **不让 AI 输出公式或裸系数**（含 `x^0.3`、`0.37`）。它只说形状名 + 档位 + 依据。
2. **不给体验维度算能力值**。哪怕用户强烈要求"我也想看关系这条线涨"——
   画的是频次与主观分，不是"关系能力 42 分"。那是编的。
3. **不把 `impact.share` 实现成"一条记录拆多条事件"**。`valence_event` 的唯一约束
   `(day_key, behavior_code, slot_key)` 会让多轴分摊要么改约束（红线）、
   要么给 `slot_key` 加轴后缀（重算与归因全部要重审）。首版只支持
   **一个主维度 + 若干体验维度**，多轴分摊观察一版再定。
4. **不打开 R8**（六之十二），新代码不引入新依赖。

---

## 八、验收

不需要 Dart SDK 就能做的：

```bash
python3 tools/parse_dart.py      # 新增文件必须 0 语法错误
python3 tools/check_symbols.py   # 新类型不漏 import
bash tools/preflight.sh          # 4d 三条守卫仍全绿
```

需要 SDK 的（在有 SDK 的机器 / CI）：

```bash
flutter analyze
flutter test test/data/ test/anchor/ test/core/ test/quant/
```

`test/quant/` 已加进 `.github/workflows/build-apk.yml`。这是**故意的**：
仓库里有 6 个红测试就是因为 `test/engine` 与 `test/capture` 从来没在 CI 上跑过（STATE 七之六）。
新写的 81 个 test 第一次上 CI 如果红了，那是它该做的事——拿真实报错回来修，
不要为了让流水线变绿去删断言。

形状层的三条数值断言（写死在测试里，防止有人"顺手优化"）：

- `shapeDose(linear, d=T) == 1.0`，其余三种同；
- 四种形状在 `0 < d < T` 区间严格单调不减；
- `d = 0.5T` 时依次为 `0.5 / 0.585 / 0.8 / 0`（±1e-6）。
