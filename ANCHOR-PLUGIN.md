# 刻度标定层（Anchor Layer）· 设计说明与边界

> 这一层解决的是：**有些事你天天在做，但没法用现成公式算它值多少。**
>
> 做法不是替你想出一个数字，而是把三件事拆开：
> 你说「怎么量」（单位），系统说「值多少」（档位 → 先验权重），
> 现实说「到底多少」（实测证据覆盖先验）。
>
> 代码：`lib/domain/anchor/`（6 个文件 / 约 2.7k 行），测试：`test/anchor/`（3 个文件 / 约 750 行）。

---

## 一、为什么没有复用现有结构

现有系统里已经有三个容易"看起来能直接塞进去"的东西，逐个说明为什么没用：

| 现成的 | 为什么不复用 |
|---|---|
| `CalibrationRecord`（`calibration_record` 表） | 它记的是**一次校准测试的结果**（体重、5RM、保持率），是证据，不是"单位定义"。硬塞进去会让"用户定义的刻度"和"实测结果"共用一张表，而这两者的可信度差一个数量级。 |
| `Confidence`（自报 0.6 / 推算 0.8 / 实测 1.0） | 它是**单条记录的可信度**，不是"这件事影响多大"。而且它的权重下限是 0.6，塞进 0.5 的上限会把枚举语义弄坏。 |
| `BalanceConfig`（64 个系数） | 它每一个字段都参与结算流水线：改一个数 → 从那天起重算 → 曲线变。而先验权重**必须**不参与结算，否则"调一下我觉得这事没那么重要"会改掉历史 EXP。 |

结论：新增一层，**对现有表的 DDL 一行不改**。这一层产出的东西先只活在内存里（本轮），落库在下一轮用新表接。

---

## 二、四个契约

代码：`anchor_models.dart`

```
UserAnchor          用户定义的单位（可信，长期复用）
  behaviorId, unitLabel, definitionText, referenceObject,
  measurementClass, referenceRangeId, calibratedAt, revisionHistory[]

DeclaredImpact      用户声明的影响（先验，会被覆盖）
  behaviorId, tier(小/中/中偏大/大), source(userPrior|aiProposal|evidence),
  weight ≤ 0.5, declaredAt, replacedBy: null | evidenceId

AnchorEvidence      实测证据（唯一的覆盖者）
  id, behaviorId, kind(校准测试|趋势反推|保持率测试|时间占比),
  measuredValue, unit, derivedTier, performedAt, confidence

AnchorCard          个人刻度卡片（Step 4 产物）= UserAnchor + DeclaredImpact + 最新证据
```

`onboarding_flow.dart` 里的 Step 1–4 就是这张卡片的**生成过程**，一次只问一个问题。

---

## 三、档位与权重的对应（唯一真源）

`anchor_config.dart`：

| 档位 | 先验权重 | AI 提议（再 × 0.6） | 可选项 |
|---|---|---|---|
| 小 | 0.15 | 0.09 | 是 |
| 中 | 0.30 | 0.18 | 是 |
| 中偏大 | 0.45 | 0.27 | 是 |
| 大 | 0.60 → 夹到 **0.50** | — | **否，只能由实测解锁** |

`priorWeightCap = 0.5` 是硬上限，`clampPrior` 在出口处夹一次，任何路径都绕不过去（有测试守着：即便把 `tierMediumPrior` 调到 0.9，出口仍是 0.5）。

---

## 四、三条硬约束是被代码强制的，不是靠自觉

| 规范原话 | 代码里的落实 | 测试 |
|---|---|---|
| 「大」只能由实测解锁 | `AnchorEngine.checkTierChange` → `code: 'large_locked'`；引导流程第 3 步的「大」选项写死"需要一次实测才能选" | `anchor_engine_test.dart` / `onboarding_flow_test.dart` |
| 先验不得作为最终结算依据 | `resolve()` 在证据落账后返回 `priorStillActive: false`，权重改用证据档位；`DeclaredImpact.weight` 从不进 `SettlementPipeline` | 同上 |
| 刻度变更不追溯 | `scopeForAnchorChange(dayKey)`：`dayKey < changedAt` 的那天仍用旧刻度，但 `mustMarkPoint: true` 要在图上标 | 同上 |

另外两条校验：

- **一次最多跳一档**（`tierJumpMax = 1`），往上调必须写理由 → `reason_required`。防"今天心情好全设成大"。
- **生理合理性复核**（`sanityCheck`）：超过参照上限 3 倍判可疑、10 倍判不合常理，处理方式是**把证据从 calibrated 降到 formula**，不阻断记录。规范要的"降置信度但不阻断"就是这个。

---

## 五、三类行为走三条路

`MeasurementClass` 决定路径，在**入口**就分流（而不是算完再打折）：

| 分类 | 例子 | EXP 权重 | 能否扣分 | 输出 |
|---|---|---|---|---|
| `formula` 可公式化 | 力量训练、睡眠、写作 | 1.0 | 能 | 公式计算 + 实测校准 |
| `subjective` 仅主观可辨 | 深度对话、情绪劳动、家务、育儿、通勤、等待、心流 | **0** | **不能** | 趋势 + 定性描述 |
| `semiObservable` 半可观测 | 拖延、被动刷手机 | 0.05 | 不能 | 时间占比，不给精确分 |

`mayDeduct` 只在 `formula` 上为 true，这条写在 `MeasurementClass` 上，任何调用点都改不了。

---

## 六、接入网页版 AI：可以，但走离线旁路

**结论：能接，而且不用加网络权限。**

App 的核心承诺之一是"无 INTERNET 权限、数据全程本地"。加一个 API 就把这句话删了。所以 `proposal_codec.dart` 走**剪贴板旁路**：

```
导出   buildRequestText(targets, config, expPerPoint)
        → 一段完整文本：硬约束 + 我们的量化公式 + 允许引用的参照区间 + 目标列表 + 严格 JSON 格式
        → 复制/分享给网页版 AI（用户自己贴）

导入   decode(raw, targets, config)
        → 剥掉 ```json 围栏和前后废话（extractJson 做括号配对，字符串内的括号不误判）
        → 逐条校验，好的一条一条进，坏的一条一条打回
        → 用户逐条确认 → toDeclaredImpact → 走和手填完全相同的先验路径
```

### 为什么 AI 适合做"具体化"，不适合做"估值"

- 具体化（"维护关系" → "一次 20 分钟不被打断、聊感受不聊安排的谈话"）是语言活，AI 强。
- 估值（这件事值 0.37 而不是 0.42）是不可验证的，AI 说什么都无法核对。

所以协议里 AI 只被允许输出**四档里的三档**（`small / medium / mediumHigh`），且必须带 `rationale` + `citation`。

### 四道闸

| 闸 | 行为 | 原因码 |
|---|---|---|
| 档位封顶 | 提「大」→ 压到「中偏大」并留一条说明 | `T_DOWNGRADED_CEILING`（`notes` 里） |
| 缺依据降档 | `citation` 为空 → 降一档 | 同上 |
| 自造数字打回 | `tier: "0.8"` → 整条拒收 | `R_FREE_NUMBER` |
| 不可核对打回 | 缺 `unit_label` / `definition_text` / `rationale` | `R_NO_UNIT` / `R_NO_DEFINITION` / `R_NO_RATIONALE` |

被拒的条目带**在 AI 回复里的序号**，用户能回去让 AI 改那一条，不用整批重来。

### 一个容易搞错的点

AI 提案经用户确认后，`source` 变成 `userPrior` 而不是继续叫 `aiProposal`。理由：确认动作让"这句话"变成了用户的判断，而系统只认"谁的判断"，不认"谁先说的"。来源留在 `note` 里（"AI 提议，已确认（依据：…）"），回看时看得见。

---

## 七、防代码污染（这一节是给下一次动手的自己看的）

### 新增了什么

```
lib/domain/anchor/anchor.dart            统一出口（调用方只 import 这个）
lib/domain/anchor/anchor_models.dart     4 个契约 + 2 个枚举 + 序列化
lib/domain/anchor/anchor_config.dart     系数表（先验权重、封顶、降档步长…）
lib/domain/anchor/anchor_engine.dart     全部判定（纯函数）
lib/domain/anchor/onboarding_flow.dart   引导流程状态机（一次一问）
lib/domain/anchor/proposal_codec.dart    网页 AI 的导出/导入协议
lib/domain/anchor/reference_ranges.dart  系统参照区间（7 张，带出处与限定）
test/anchor/*.dart                       3 个测试文件
```

### 改动了什么

**零。** 现有 128 个 Dart 文件一行没动（`parse_dart.py` 前后都是 128 个文件全部通过）。唯一被编辑的既有文件是 `tools/preflight.sh`（加了一条守卫，见下）。

### 三条机器守卫（`tools/preflight.sh` 第 4d 节）

```
1. lib/domain/anchor/ 不许 import flutter / sqflite / share_plus / data / presentation / services
2. lib/domain/{engine,settlement,science,behaviors,capture,forecast} 不许 import anchor
3. lib/domain/anchor/ 的代码里不许出现 daily_log
```

第 2 条是最要紧的：**结算层一旦 import 了 anchor，"先验"就会顺着计算链爬进历史 EXP**，而这正是这一层存在的理由的反面。这条守卫是硬拦，不靠 review。

### 下一轮的空间在哪（允许改的地方）

| 下一轮要做 | 允许动的文件 | 不许动的文件 |
|---|---|---|
| 落库：4 张新表（`user_anchor` / `declared_impact` / `anchor_evidence` / `anchor_revision`） | `schema.dart` 追加、`migrations.dart` 追加 v3、新增 `anchor_dao.dart` | 既有 17 张表的 DDL（一条也不改） |
| 仓储 + 幂等写入 | 新增 `anchor_repository.dart` | `CaptureRepository.commit` 的签名与语义 |
| 刻度标定页 / 提案导入页 | 新增 `presentation/anchor/`、`providers.dart` 只加 provider | `home/chart/detail` 的既有布局 |
| 图上的空心点 + 虚线带 | `settlement_chart_painter.dart` 加**一层**（走 `WeightResolution.marker`） | 四层叠加的既有顺序 |
| AI 导出/导入入口 | 复用 `export_service.dart` 的 share 通道，或 `Clipboard.setData` | 新增任何网络依赖 |

**红线**：`INTERNET` 权限、任何 HTTP 客户端、"云端同步"、把 `anchor` 概念塞进 `SettlementPipeline`。

---

## 八、验收状态

已验证（不需要 Dart SDK）：

```
python3 tools/parse_dart.py      → 128 个文件，0 语法错误
python3 tools/check_symbols.py   → 351 个符号，无缺失 import
bash tools/preflight.sh          → 4d 三道守卫全绿（1/2 节的 ✗ 是沙箱无 SDK 的既有状态）
```

未验证（沙箱无 Flutter SDK，必须在有 SDK 的机器上跑）：

```
flutter analyze
flutter test test/anchor/
```

已知的静态类型风险点（写测试时按最严格的方式写的，但仍需真编译器确认）：

- `OnboardingFlow.declareTier` 返回 record `({OnboardingState state, TierChangeVerdict verdict})`——Dart 3 的命名 record，`parse_dart.py` 认得，但 `flutter analyze` 会给出更强的约束检查。
- `OnboardingState.fromJson` 里 `Map<Object?, Object?>` 的协变判断，运行时依赖 `jsonDecode` 的返回形状（`Map<String, dynamic>`）。
- `anchor_config.dart` 的 `ImpactTier.values[tierIndex]`：索引已显式夹取（`int.clamp` 返回 `num`，这里没用 clamp）。
