# 经验账本 · 工程状态（交接文件）

> 这个文件是为了跨会话续接而写的。新会话第一件事：读它，然后从「下一步」继续。

## 一、项目一句话

Flutter + Dart 本地 Android App：用可查证的科学公式，把行为带来的"突触变化"
画到一张长期图表上。数据全程本地，无网络权限、无账号、无埋点。

工程根目录：`/workspace/exp_ledger/`

## 二、进度

- 第 1 步 ✅ 架构概览 + 完整文件树 + 采集流程与加减分决策流程图
- 第 2 步 ✅ 采集窗口（行为库 28 条 / 引导状态机 / 即时回执 / UI 三屏）
- 第 3 步 ✅ 算法层（公式 / Valence Engine / 负荷损伤 / 预测 / 106 个测试）
- 第 4 步 ✅ **数据层**（17 张表 / 17 个 DAO / 7 个仓储 / 幂等写入 / 级联重算）
  详见 `STEP4-DATA-LAYER.md`；DDL 已用真 SQLite 验收（`tools/schema_check.py`）
- 第 5 步 ✅ UI 逐页：首页 / 曲线 / 明细 / 实验室 / 设置 5 页 + Riverpod 接线 + 确认闭环发起侧
  （`AppShell` 五 tab，FAB 只在非设置页出现）
- 第 6 步 ✅ 通知 / 导出 / 主题规范 / 桌面小组件
  （本地提醒、share_plus 导出、63 系数收进 Tokens、Kotlin AppWidget + MethodChannel）
- 第 7 步 ✅ 构建打包：CI 已跑通，**APK 已产出**
  仓库 https://github.com/ruiokd/exp-ledger（公开）
  产物 `dist/exp-ledger-1.0.0.apk`（31MB，arm64 + armv7，sha256 9929d479…）
  沙箱仍是 aarch64，产不出 APK；构建在 GitHub Actions 的 x64 runner 上完成

## 三、当前规模

107 个 Dart 文件 / 约 19.2k 行；数据层 32 个文件 / 4.4k 行；UI 层 17 个文件 / 5.8k 行；
Android 平台层 14 个文件（Kotlin + manifest + res）。测试 9 个文件 / 2.1k 行。

已经能跑的部分：`main.dart` 开库 → 补算脏日 → `ProviderScope` 注入 → `AppShell` 四页。
采集窗口从 FAB 进入，确认后落库、刷新全部读接口、并排一条次日确认。
`harness_page.dart` 已删除——两套写法会让人在错误的文件里改代码。

## 四、五条不能破坏的架构铁律

1. **domain 层零 Flutter 依赖**：`lib/domain/**` 只 import `dart:core`/`dart:math`，
   因此全部算法能用纯 `package:test` 跑，不需要模拟器。
2. **单一写入通道**：只有 `CaptureRepository.commit(DraftEntry)` 能写库。
   幂等键 = `dayKey|behaviorCode|slotKey`。
3. **结算是可重放的纯函数**：`SettlementPipeline.settle(input)` 无副作用，
   历史修正后从某天重跑到今天即可收敛。任何一步引入随机/时钟都会破坏它。
4. **安全闸在流水线第 0 位**：`SafetyGate` 触发时暂停当日结算，不算分也不扣分。
5. **系数只住在 `BalanceConfig`**：任何算法文件里不允许出现裸数字系数。

## 五、关键实现约定（改代码前必看）

- `DraftEntry` 是采集层与算法层之间唯一的契约，字段含：
  `dayKey / behaviorCode / category / valence / axis / planStatus / confidence /
   slotKey / answers / metrics / interpretation / doseFraction / isInterruption`。
- `valence` 是**推导后**的价（`behavior.valenceOf(derived)`），不是静态值——
  睡眠一次录入可能正也可能负。
- 负向剂量取 `max(熬夜越界分钟, 睡眠缺口×60)`，**不相加**（否则一次熬夜罚两遍）。
- 负向 EXP **不乘状态乘数**（否则同一件事被罚两次）。
- 超额判定顺序不可交换：疲劳 → ACWR → 恢复间隔 → 才算有益超额。
- 归因键格式 `behaviorCode@yyyy-MM-dd`，同键只扣罚得最重的那条。

## 六、数据层结构（第 4 步产物，改之前必看）

17 张表 = 清单 14 张 + 3 张内部表（`daily_log_history` / `day_settlement` / `dirty_day`）。
为什么必须多这三张，见 `STEP4-DATA-LAYER.md` 第 1 节。DDL 全在 `lib/data/db/schema.dart`。

- **写入只有一个门**：`CaptureRepository.commit(DraftEntry)`。
  别的仓储都不许碰 `daily_log`。内容未变 → 不标脏、不重算。
- **三条唯一约束**：`daily_log(idempotency_key)`、
  `valence_event(day_key, behavior_code, slot_key)`、
  `negative_event(day_key, root_cause_key) WHERE is_primary = 1`（**部分**索引，
  只挡主因，后果记录可以多条）。
- **重算顺序不可交换**：删旧产物 → 预取原始记录 → 逐日
  （负荷 → 结算 → 事件 → 结算行 → 快照 → 预测）→ 清脏日。
  删负向事件必须在结算前，否则 `existingRootKeys` 会吃到自己上一轮的结果。
- **状态恢复取"最近一条早于该日的 `state_after`"**，不是 `day-1`：
  断更几天不该把负债清零。
- **`forecast_point.day_key` 是生成日**，`horizon_days` 是往后第几天。
  历史线查 `horizon_days = 0`；"今天往后看"查 `day_key = 今天`。
- **等级靠 `applyExp` 复算**，不是 `totalExp + netExp`（负向先被缓冲池吸收）。
- 重算串行化：`SettlementRepository` 内部有 Future 链，两次并发会互删产物。
- 新加 11 个系数已进 `BalanceConfig`（能力回退/折算/完整度/预测步长/复习间隔等），
  数据层没有裸数字。

验收：

```bash
python3 tools/schema_check.py     # 抽 schema.dart 的 DDL 在真 SQLite 上跑，验约束
flutter analyze                   # 沙箱没有 SDK，必须在有 SDK 的机器上跑
flutter test test/data/           # sqflite_common_ffi 开内存库，不需要模拟器
```

## 六之补、UI 层结构（第 5 步，改之前必看）

```
lib/presentation/
  providers.dart            所有仓储的 Riverpod 供应商；UI 里不许 new 仓储
  shell/app_shell.dart      四页 + 自绘底部栏 + 采集入口 + 确认任务发起
  home/home_page.dart       今日净 EXP / 等级进度 / 五维 / 待确认 / 今日记录
  chart/chart_page.dart     轴与区间选择、图例、数字摘要
  chart/settlement_chart_painter.dart   CustomPainter 四层叠加
  detail/detail_page.dart   某天的算式、正负事件、归因、回补路径、原始记录
  settings/settings_page.dart  档案、数据概况、系数覆盖、导出/重算/清空
  lab/lab_page.dart         数值实验室：63 个系数全部可覆盖，滑杆/精确值 → 重算 → 曲线变
```

- **曲线 x 轴按真实日期排布**，不按点序号。预测是每 3 天一格，
  按序号排会把 90 天预测画得和 30 天一样长。
- 四层顺序固定：中断期底色 → 风险区底色 → 置信带/修正增益带 → 曲线与今天分界。
  底色被曲线压住，才看得出"这段时间发生了什么"。
- **总经验不外推**：预测只有五维。给"未来会有多少级"编一条线没有可查证依据。
- 首页每个数字都能在明细页找到算式：基础 + 精致 + 效率 → ×权重 ×状态 ×置信 ×每点。
- 负向不用红色（`AppColors.negative` 是石板蓝灰）；没有连续天数威胁、没有排行榜。
- 采集提交后：落库 → `_invalidateAll()` → 排一条次日确认（仅自报的正向记录，
  同键只排一次）。确认失败不影响已落库的记录。
- 数值实验室的写入顺序不可反：`set()` → `recomputeFrom(90 天前)` → `invalidate`。
  先 invalidate 会让页面拿到旧曲线再刷新，看起来像"改了没生效"。
- 实验室里每个系数都有中文标签 + 一句"它管什么"；滑杆给范围，输入框给精度。
  未知键会被 `ConfigRepository.set` 拒掉（白名单来自 `kDefaultConfig.toMap()`）。

## 六之三、平台层（Android）

```
android/
  settings.gradle.kts / build.gradle.kts / gradle.properties
  gradle/wrapper/gradle-wrapper.properties   Gradle 8.7（jar 待补，见下）
  app/build.gradle.kts                       AGP 8.3.2 / Kotlin 1.9.22 / compileSdk 34 / minSdk 23
  app/src/main/AndroidManifest.xml           通知权限、开机重排、小组件 receiver
  app/src/main/kotlin/com/yg/ledger/MainActivity.kt         MethodChannel `exp_ledger/widget`
  app/src/main/kotlin/com/yg/ledger/LedgerWidgetProvider.kt  小组件渲染（只读 SharedPreferences 缓存）
  app/src/main/res/...                       widget 布局、圆角背景、单色通知图标、主题
```

- **没有 INTERNET 权限**：整个 App 本地跑，能连网也不需要。
- 小组件只显示三个数字：今日净 EXP、等级、待确认数。**不放连续天数、不放排行**——
  桌面小组件天天在眼前，放什么就等于在暗示什么。
- 小组件不做计算：Dart 侧算好字符串，经 `WidgetBridge` 推给 Kotlin 写缓存，
  `AppWidgetManager` 只负责渲染。在 Kotlin 里再实现一遍算法必然漂移。
- 提醒用 `AndroidScheduleMode.inexactAllowWhileIdle`，**不申请 SCHEDULE_EXACT_ALARM**：
  每天一次的提醒不需要精确到秒，少一个敏感权限。
- 时区用"本地时间算出的绝对时刻 + UTC location"，不依赖额外时区插件；
  DST 地区在切换后可能偏一小时（每次启动都会重排，影响最多一天）。
- `app_setting` 表是 v2 迁移加进来的（第 4 步写的 upgrade 骨架第一次真用上）。
  提醒开关/时间不进 `config_override`：那张表只放算法系数，混在一起会导致
  "改了个提醒时间把曲线重算了"。

## 六之四、构建（第 7 步现状）

**已跑通**：2026-11-12 第一次成功构建（5 分 40 秒），产物是 31MB 的
`app-release.apk`，manifest 里 `com.yg.ledger` / `MainActivity` /
`LedgerWidgetProvider` / `POST_NOTIFICATIONS` / `RECEIVE_BOOT_COMPLETED` 都在，
`INTERNET` **不在**（验证了"全本地"这条承诺）。

六次失败与修法（顺序即真实排查顺序，下次直接按这张表走）：

| # | 报错 | 原因 | 修法 |
|---|---|---|---|
| 1 | 预检失败 | 仓库里只有 `gradle-wrapper.properties`，缺 jar 与 gradlew | CI 里用 `flutter create` 生成模板，只复制 jar 与 gradlew |
| 2 | `pub get` 版本无解 | `test ^1.25.8` 要 test_api 0.7.3+，Flutter 3.24.5 钉 0.7.2 | `test: ^1.25.7` |
| 3 | analyze 8 error | 配置表重复键、缺 num_ext、notification 缺 `uiLocalNotificationDateInterpretation`、测试签名不同步 | 逐个修，详见提交 `29fb859` |
| 4 | 测试 `Bad state: No element` | 用例漏了 `commit` 就去读库 | 补 commit |
| 5 | `Minimum supported Gradle version is 8.4` | `flutter create` 的模板 wrapper 是 8.3，覆盖了仓库里的 8.7 | 复制 wrapper 时**排除** properties |
| 6 | `requires core library desugaring` | flutter_local_notifications 的 AAR 硬要求（minSdk < 26） | `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.0.4` |

**沙箱产不出 APK，原因不是缺 SDK，是架构。** `aapt2` / `zipalign` 只有 x86_64
的 ELF，在 aarch64 上直接 `Exec format error`；本机没有 qemu/box64，
PRoot 下装 binfmt 转译不现实。JDK 17 有，Flutter / Android SDK / Gradle 都没有。

已经就绪的东西：

| 文件 | 作用 |
|---|---|
| `.github/workflows/build-apk.yml` | 推送即出 APK（ubuntu-latest x64，含 analyze/test 门禁，artifact 保留 30 天） |
| `tools/preflight.sh` | 工具链、android/ 完整性、包名三处一致、静态检查 |
| `tools/build_apk.sh` | 预检 → pub get → analyze → test → build，一条命令 |
| `STEP7-BUILD.md` | 版本矩阵 + 11 条报错预案 + 装机五步验收 |

**能在沙箱里做的验证，已经全做了**（都不需要 Dart SDK）：

```
python3 tools/check_symbols.py   # 跨文件符号：找出「用了项目内类型但没 import」
python3 tools/parse_dart.py      # tree-sitter 解析全部 .dart，抓真正的语法错误
python3 tools/schema_check.py    # 抽出 DDL 在真 SQLite 上跑，验约束
bash tools/preflight.sh          # 以上全跑 + 工具链检查
```

`parse_dart.py` 装的是 `tree_sitter` + `tree_sitter_dart`，认得 Dart 3 的
record / 增强枚举 / switch 表达式 / 字符串插值，比手写括号计数可靠得多。
**它抓出了第 3 步留下的真 bug**：`valence_engine.dart` 里把变量命名为 `late`
（Dart 内置标识符），那一行必然编译失败。

## 七、已知待办与坑

- **`android/gradle/wrapper/gradle-wrapper.jar` 还没有**（生成不了二进制）。
  第 7 步第一件事：先 `cp -r android android.bak`，再 `flutter create --platforms=android .`
  补齐 wrapper jar / local.properties / .gitignore，然后 `diff -r android.bak android`
  确认它没覆盖手写的 manifest 与 Kotlin 文件。
- Android 工程**从未构建过**（沙箱没有 SDK 与 Gradle）。
- 第 3 步的 domain 代码在接入 `parse_dart.py` 之前**从未做过语法验证**；
  已发现 1 处（`late` 变量名）并修复。语法通过 ≠ 类型通过，`flutter analyze` 仍可能报错。AGP 8.3.2 + Gradle 8.7 +
  Kotlin 1.9.22 是 Flutter 3.24 的默认组合，但没验证；报错优先看版本匹配。
- 沙箱（aarch64 / PRoot）**没有 Flutter SDK**，第 2–4 步的代码都还没有经过
  `dart analyze` / `flutter analyze`。第 7 步必须在有 SDK 的机器上先跑
  `flutter analyze` + `flutter test`，按报错逐个修。
  已经手工摘掉的坑：`.clamp()` 返回 `num` 需 `.toDouble()`、`switch` 语句一律改 if/else 链、
  sqflite 只接受 num/String/null/Uint8List（Map 必须先 jsonEncode）。
- **事务体内只能用 `txn`**：在 `db.transaction` 里改用 `db` 会等自己持有的锁 → 死锁。
  重算与提交都遵守这条（重算放在事务外由 `commit` 调用）。
- 数据层测试要 `sqflite_common_ffi`：`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`，
  之后 `AppDatabase.openInMemory()` 就能开真内存库。
- 桌面小组件已实现（Kotlin `AppWidgetProvider` + MethodChannel），但**未构建过**。
- 语音输入强制离线（`EXTRA_PREFER_OFFLINE`），设备不支持时隐藏按钮，绝不申请 INTERNET。
- 图表主曲线必须 `CustomPainter` 自绘（置信带 + 衰减带 + 风险区 + 中断期底色四层叠加），
  fl_chart 只用于雷达图与堆叠条。
- 摄入热量目前没有采集入口，`EnergyLedger.intakeKcal` 会为 0 并标"空缺"，
  第 5 步加饮食采集后再补。
- ACWR 依赖记录里的 `session_minutes|minutes` 与 `rpe|rir`。行为入口不写这两个字段，
  该次训练对负荷的贡献就是 0——不加假数据，缺就是缺。
- `day_settlement.revision` = 这一天被重算过几次（删除前先读旧值再加一）；
  不是"用户修订次数"，用户修订看 `daily_log.revision` + `daily_log_history`。

## 八、续接提示词（新会话直接粘这段）

> 继续做经验账本项目。先读 `/workspace/exp_ledger/STATE.md`，
> 里面是完整的进度、架构铁律、数据层结构与实现约定。
> 数据层已完成（17 张表 / 幂等写入 / 级联重算 / test/data 三个测试）。
> 第 6 步已完成。现在开始第 7 步：构建打包。
> 顺序：① 备份 android/ → `flutter create --platforms=android .` 补 wrapper →
> `diff -r` 确认没覆盖手写文件；② `flutter pub get`；③ `flutter analyze`，
> 按报错逐个修（重点怀疑：Riverpod family 的回调签名、record 泛型、
> `dart:ui` 的 PathMetric、flutter_local_notifications 17 的权限 API）；
> ④ `flutter test test/data/`（sqflite_common_ffi，不需要模拟器）；
> ⑤ `flutter build apk --debug` → 装机实测：记录一条 → 杀进程重开看是否还在 →
> 打开提醒等它响 → 桌面加小组件看数字是否跟着变 → 导出看分享面板。
> 全绿后写一份依赖清单与已知限制。

## 九、交付给用户时的语气约定

- 中文回复，直接、具体、可操作。
- 科学公式一律标注出处 + 误差 + 是否简化；无法确证的标"待核实"，绝不编。
- ACWR / sRPE 必须写明"竞技体育外推，非普通人群诊断"。
- 涉及损伤风险必须给就医指引，App 不下诊断。
- 负向文案中性，不羞辱、不红色警报、不断签清零、无排行榜。
