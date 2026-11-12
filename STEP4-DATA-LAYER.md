# 第 4 步 · 数据层 交付说明

> 目标：把 `lib/data/` 写完，让 harness 换成真数据库。
> 结论：**写完了**。31 个文件 / 4231 行，17 张表，7 个仓储，写入全走一个口子，
> 历史修正能级联重算并且可重放收敛。

---

## 1. 表结构：清单 14 张 + 3 张内部表

STATE.md 原清单列了 14 张（正文写 13，按清单为准）；另外补了 3 张**必需**的表：

| 表 | 用途 | 为什么必须有 |
|---|---|---|
| `daily_log_history` | 修订链 | 覆盖同一幂等键时，旧版本整行归档；否则"我改过什么"不可追 |
| `day_settlement` | 结算产物 | 存 `state_before/after`，让"今天的状态"不必在内存里背着整条历史 |
| `dirty_day` | 脏日队列 | 进程被杀不丢重算任务；下次启动 `recomputePending()` 接着跑 |

`day_settlement` 不是多余的：`AbilitySnapshot` 只有等级/总经验/缓冲池，
存不下 `StateVars`（睡眠负债、损伤负荷、恢复债、一致性）。
把它塞进快照会让"能力雷达"和"状态变量"两个概念混在一张表里。

## 2. 三条唯一约束，各管一件事

| 索引 | 类型 | 挡什么 |
|---|---|---|
| `ux_daily_log_idem(idempotency_key)` | 唯一 | 同日同行为同槽位只留一行 |
| `ux_valence_slot(day_key, behavior_code, slot_key)` | 唯一 | 重算时同槽位不会出现两条正向事件 |
| `ux_negative_primary(day_key, root_cause_key) WHERE is_primary = 1` | **部分**唯一 | 同根因只扣一次主因；后果记录（`exp = 0`）可以多条 |

第三条是部分索引，不是普通唯一索引——这一点很关键：
真按 `(root_cause_key, day_key)` 全表唯一，`_dedupe` 产生的后果记录就插不进去，
归因去重会直接失效。

## 3. 写入：只有一个门

```
DraftEntry → CaptureRepository.commit()
                ├ 库里没有       → insert，标脏
                ├ 有且内容相同   → 什么都不做（不标脏、不重算）
                └ 有但内容不同   → 旧行归档 → revision+1 → 覆盖 → 标脏
           →（若注入了 SettlementRepository）recomputeFrom(那天)
```

"内容相同"比较的是会影响结算的字段（剂量、计划状态、置信度、答案、指标、中断标记），
并且把 Map **按键排序后**再比——否则 `{sets:4, rir:2}` 与 `{rir:2, sets:4}`
会被判成两次不同的输入，白跑一遍重算。

## 4. 重算：顺序不可交换

```
删当日旧产物（正向 / 负向 / 结算 / 快照 / 预测）
  → 预取窗口内原始记录（内存索引）
  → 逐日：负荷 → 结算（安全闸在第 0 位） → 写事件 → 写结算 → 写快照 → 写预测
  → 清脏日
```

两个细节决定了它能不能收敛：

1. **必须先删负向事件再重算**。`existingRootKeys` 是从库里读的，
   如果不删，上一轮自己写的根因键会被当成"历史已经扣过"，
   第二天所有负向都变成后果记录——跑第二次和第一次结果不同，就不叫重放了。
2. **状态从 `day_settlement` 取"最近一条早于该日的 state_after"**，不是取 `day-1`。
   中间断更三天，负债不会被清零——否则"停更"反而成了回血手段。

`_serialized` 把重算串成一条链：两次并发重算会互删产物，必须排队。

## 5. 预测表的语义（容易混，写死在 DAO 注释里）

```
day_key      = 哪一天做出的预测（生成日）
horizon_days = 从生成日往后第几天（0 = 当天实际值）
```

- 主图历史线读 `horizon_days = 0`
- "今天往后看 90 天"读 `day_key = 今天`
- 只有**最后一天**写完整预测序列（31 点 × 5 轴），历史每天只写 1 点 × 5 轴

## 6. 数值链路：等级不能靠累加

`DaySettlement` 只留了 `levelBefore/levelAfter/bufferAfter`，**没有 `totalExp`**。
所以快照里的累计经验必须用 `applyExp(前一天三元组, 今天净经验)` 复算——
直接 `totalExp + netExp` 是错的：负向经验先被缓冲池吸收，
只有超出部分才真的扣累计值。复算用的是领域层同一个函数，保证同源。

## 7. 系数仍然只有一个家

新增的 11 个系数全部落在 `BalanceConfig`：

```
abilityBaseline / abilityCap / abilityDecayPerDay / abilityPerExp
completenessWindowDays / forecastHorizonDays / forecastStepDays
srpeDefaultRpe / memoryReviewBaseDays / memoryReviewGrowth / memoryReviewMaxDays
```

数据层没有任何裸数字系数：能力回退、EXP 折算、完整度窗口、sRPE 缺省 RPE、
复习间隔增长，全部从配置取。数值实验室改一个键 → 重算 → 曲线跟着变（有测试）。

## 8. 验收方式（沙箱没有 Dart/Flutter SDK）

两件事分开验：

1. **DDL 与数据库约束**：`python3 tools/schema_check.py`
   从 `schema.dart` 里正则抽出 30 条语句，在真 SQLite 3.45 上执行，
   然后实测：重复幂等键被拒、`INSERT OR REPLACE` 仍一行、
   同根因第二条主因被拒、后果记录可多条、预测点主键生效。
   **当前结果：全部通过**（17 张表，关键索引齐全，括号/引号平衡检查也过了）。

2. **Dart 侧**：需要在有 SDK 的机器上跑
   ```
   flutter pub get
   flutter analyze
   flutter test test/data/
   ```
   测试用 `sqflite_common_ffi` 开真 SQLite 内存库，不需要模拟器。
   三个测试文件：
   - `schema_test.dart`：17 张表、关键索引、三条唯一约束真的在库层生效
   - `idempotency_test.dart`：同键两次 / 内容不变不标脏 / 修订归档 / 撤销留档
   - `replay_test.dart`：改历史剂量 → 今天变化 / 重跑两次完全一致 /
     改系数 → 曲线变 / 安全闸日原地不动 / 脏日与 clamp 行为

## 9. 这一步还没做的（第 5 步的事）

- `EnergyLedger` 的摄入热量仍无采集入口，`intakeKcal` 会为 0 —— 不做假数据填充。
- `srpeToday` 依赖记录里的 `session_minutes|minutes` 与 `rpe|rir`；
  行为库里如果有入口没写这两个字段，该次训练对 ACWR 的贡献就是 0（不是错，是缺数据）。
- 摄入/消耗的六层账本还没接进结算流水线（等领域层决定它算不算分）。
