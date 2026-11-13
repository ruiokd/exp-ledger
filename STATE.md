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
- 第 7 步 ✅ 构建打包：CI 已跑通，**APK 已产出**（v1.0.1 签名固定）
  仓库 https://github.com/ruiokd/exp-ledger（公开）
  产物 `dist/exp-ledger-1.0.0.apk`（31MB，arm64 + armv7，sha256 9929d479…）
  沙箱仍是 aarch64，产不出 APK；构建在 GitHub Actions 的 x64 runner 上完成
- 第 7 步补 ✅ **v1.0.2 修启动崩溃**：根因已确诊（Android 14 execSQL 拒绝 PRAGMA），
  改 `rawQuery` + 吞异常；`versionCode 3 / 1.0.2`，pubspec 与 gradle 已同步。
  新增回归测试 `test/data/app_database_test.dart` + preflight 两条静态门禁（见六之六）
  **APK 已产出**：`dist/exp-ledger-1.0.2.apk` / `/chat/outputs/` 同名副本，
  31.7 MB，sha256 `886f02af…5682a5`，CI run 43293073012 全绿（analyze 0 error/0 warning，
  数据层测试含新用例通过）
- 第 13 步 ✅ **自建项目管理（v1.2.1）**：编辑 / 删除 UI + `update()` 同事务改
  两个真源（`custom_behavior.target_dose` 与 `behavior_quant_spec.target_dose`）。
  入口：刻度标定页 →「管理自建项目」。版本 `1.2.1+10`，细节见六之十四。
- 第 12 步 ✅ **日志纪律（v1.1.4）**：不记用户自由文本；上次运行单独分节，
  `errorCount` 只数本次；日志页加「含上次运行」开关。详见六之十三。版本 `1.1.4+8`
  **APK 已产出**：`dist/exp-ledger-1.1.4.apk` 与 `/chat/outputs/` 同名副本，33 MB，
  sha256 `f6a434b35f4eec5d…`，CI run 43368361786 全绿
- 第 11 步 ✅ **自建项目（v1.1.3）**：新表 + DAO/Repository + AI 提示词与解析 + 新建页 +
  采集页/刻度页两个入口 + 关 R8（细节见六之十一、六之十二）。版本 `1.1.3+7`
  **APK 已产出**：`dist/exp-ledger-1.1.3.apk` 与 `/chat/outputs/` 同名副本，33 MB，
  sha256 `133e47cf31a9555c…`，CI run 43364683929 全绿（analyze 0 error/0 warning，
  `test/data/ + test/anchor/ + test/core/`）。包内已验：`ic_notification` 在 arsc、
  `INTERNET` 不在、Gson 类名完整保留（关 R8 生效）、`versionName 1.1.3`
- 第 10 步 ✅ **v1.1.2 UI 修正**：x 轴标签防重叠 / 预测按区间截断 / 区间信息行 /
  FAB 居中 / 通知图标 keep.xml + 通知初始化全降级。详见六之十。版本 `1.1.2+6`
  **APK 已产出**：`dist/exp-ledger-1.1.2.apk` 与 `/chat/outputs/` 同名副本，32 MB，
  sha256 `477e3fd770805b15…`，CI run 43359383485 全绿。
  **图标修复有硬证据**：`resources.arsc` 里 `ic_notification` 在 1.1.2 存在、
  在 1.1.1 **不存在**（同一检查脚本），说明 `res/raw/keep.xml` 真的把资源保住了
- 第 9 步 ✅ **运行日志（v1.1.1）**：环形缓冲 + 落盘 + 全局钩子 + 日志页 + 启动失败页入口
  设计见六之九；`test/core/app_log_test.dart` 9 个用例；版本 `1.1.1+5`
  **APK 已产出**：`dist/exp-ledger-1.1.1.apk` 与 `/chat/outputs/` 同名副本，32 MB，
  sha256 `ce6b08808803d0fc…`，CI run 43356112915 全绿（`test/data/` + `test/anchor/` +
  `test/core/`）。manifest 已验：`INTERNET` 不在，`versionName 1.1.1` / `versionCode 5`
- 第 8 步 ✅ **刻度标定层（Anchor Layer）全链路：domain + 数据层 + UI**
  设计说明见 `ANCHOR-PLUGIN.md`
  domain `lib/domain/anchor/` 6 文件 / 2.75k 行；数据层 `anchor_dao` + `anchor_repository` 491 行；
  UI `lib/presentation/anchor/` 5 文件 / 1.5k 行；测试 4 文件（domain 3 + 数据层 1）
  覆盖：单位定义（UserAnchor）／档位声明（DeclaredImpact，≤0.5）／实测覆盖
  （AnchorEvidence → `replacedBy`，同一事务）／引导流程 Step 1–4（一次一问）／
  系统参照区间 7 张／**网页版 AI 的离线提案协议**（导出请求文本 → 粘回复 → 逐条校验 →
  用户确认）／四档横轴「先验空心点 vs 实测实心点」小图
  schema 升到 **v3**（4 张新表，既有 17 张一条未改）；版本号 `1.1.0+4`
  静态验收全绿（parse 136 文件 / 符号 359 / DDL 真 SQLite / preflight 4d 三道边界守卫）
  **APK 已产出**：`dist/exp-ledger-1.1.0.apk` 与 `/chat/outputs/` 同名副本，
  31.0 MB，sha256 `403c0176c2888c22…`，CI run 43352669660 全绿
  （analyze 0 error / 0 warning；`test/data/` + `test/anchor/` 全通过）。
  manifest 已验：`INTERNET` **不在**，`POST_NOTIFICATIONS` / `RECEIVE_BOOT_COMPLETED` 在，
  `versionName 1.1.0` / `versionCode 4`

- **v1.2.0 已出包（量化形状层 + 自建维度注册表）**：`dist/exp-ledger-1.2.0.apk`
  与 `/chat/outputs/` 同名副本，34.6 MB，sha256 `7f83601e7da83089…`
  CI run 43375143712 全绿（analyze 0 error/0 warning，`test/data/ test/anchor/ test/core/ test/quant/`）。
  包内已验：`INTERNET` **不在**、`versionName 1.2.0`、`com.yg.ledger`、
  `POST_NOTIFICATIONS`/`RECEIVE_BOOT_COMPLETED` 在、`resources.arsc` 里 `ic_notification` 在、
  `libapp.so` 里 `behavior_quant_spec` / `axis_definition` / `duration_min` / `saturating` 都在
  （= v5 迁移与量化层确实编进包里了）。版本 `1.2.0+9`
  **首跑红过一次**：协议写 `duration_min`、枚举叫 `durationMin`，`tryParse` 只认 `.name`，
  5 条 protocol 测试红；补 `wire` 名、两套都认（commit `25225d4`）。
- **待装机验证（v1.2.0，按顺序）**：① 能进首页 = v5 迁移通过（失败页阶段应是「迁移」）；
  ② 设置 → 新建项目，说「看一场电影」→ 预览里把「怎么折算」选事件型 → 创建；
  ③ 记一次：0.5 次应为 0 分、1 次应为满分，回执里要有「折算方式：事件型」那行；
  ④ 老的自建项目记一次，分数应与 1.1.4 完全一致（linear 等价）；
  ⑤ 杀进程重开，口径还在（`behavior_quant_spec` 落库）。

## 三、当前规模

130 个 Dart 文件（lib）/ 约 25k 行；17 个测试文件 / 3.6k 行（含本轮 quant 2 文件）。
v1.2.0：lib 164 个文件（含 quant 8 + custom_behavior_def + shape_picker）/ 测试 22 文件。
第 8 步新增：domain 6 文件 2.75k 行 + 数据层 2 文件 491 行 + UI 5 文件 1.5k 行 + 测试 4 文件。
数据层原 32 文件 / 4.4k 行；UI 原 17 文件 / 5.8k 行；Android 平台层 14 文件。

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
- **写库语句的分工**：`execute` 只跑没有结果集的 DDL/DML；`PRAGMA`/`SELECT`/`EXPLAIN`
  一律 `rawQuery`。Android 14 起违反这条会在 `execSQL` 抛异常，而 `onConfigure` 里中招
  就是启动崩溃（六之六的事故）。开库钩子里的每条语句都要 try/catch。
- **归因键格式** `behaviorCode@yyyy-MM-dd`，同键只扣罚得最重的那条。

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

## 六之五、事故记录：v1.0.0 装机黑屏（2026-11-12）

**现象**：装上能打开但全黑，屏幕里一个 UI 节点都没有；系统不弹"应用已停止"；
反复点开后手机明显变卡。

**定位过程**（都做了，别再重走）：
1. `phone_control.read_screen` → App 在前台，只有空 `FrameLayout`，**Flutter 首帧没渲染**；
2. 设置里清除数据（数据 20.48 KB → 0）→ 重开仍黑屏 → **不是脏数据/迁移问题**；
3. 拆 APK 查 dex：`GeneratedPluginRegistrant` / `SqflitePlugin` / `dexterous/flutterlocalnotifications`
   都在 → **不是插件没注册**；
4. 看 `main.dart`：`await AppDatabase.open()` 在 `runApp` **之前且无保护**。

**根因判断**：`runApp` 之前的 await 一旦抛异常或挂起，界面永远不会被创建；
因为没有 native crash，系统也不弹错误框，用户只能看到黑屏。
（当时是"抛异常还是挂起"两种可能，v1.0.1 的诊断页给出了答案：**抛异常**，见六之六。）

**修法（v1.0.1）**：
- 开库加 8 秒超时 + `try/catch`，失败渲染 `StartupFailureApp`（带阶段、错误、堆栈、复制按钮）
- 覆盖 `ErrorWidget.builder`：release 的灰屏换成可读页面
- 失败页带「再试一次」，重跑完整 boot 流程

**v1.0.1 已发布**（commit b49d21d，versionCode 2）：
- 签名已固定：`android/app/debug.keystore` 进仓库，CI 与本地同指纹
  （SHA-256 `56:44:75:47…D2:71:52`），以后构建可直接覆盖升级；
  v1.0.0 → v1.0.1 仍需卸载一次（旧包的临时签名无法复现）。
- 待办：~~等用户回传诊断页文本~~ **已回传，根因已确诊 → 见六之六**。

**教训（写进技能）**：
- `runApp` 之前只允许"极轻、带超时、可失败"的操作；
- 任何 release 包都必须有"启动失败也能说话"的路径，否则用户只看到黑屏，排查成本极高；
- 用户描述"卡"往往是"启动失败被反复重试"，不是设备性能问题。
- 诊断页的第一版设计是对的：**把阶段 + 原文 + 堆栈一起显示**，否则一行
  `DatabaseException` 根本猜不出是不是自己写的 SQL。

## 六之六、事故记录：v1.0.1 启动崩溃（Android 14 / PRAGMA）— 已确诊并修复

**用户回传的诊断页原文**（v1.0.1，装机即现）：

```
阶段：打开数据库
错误：DatabaseException(unknown error (code 0 SQLITE_OK):
      Queries can be performed using SQLiteDatabase query or rawQuery methods only.)
      sql 'PRAGMA busy_timeout = 5000' args []
#3 AppDatabase.open.<anonymous closure> (package:exp_ledger/data/db/app_database.dart:52)
```

**根因（不是猜的，是异常文本直接给出的）**：

`lib/data/db/app_database.dart:52` 的 `onConfigure` 里写了
`await db.execute('PRAGMA busy_timeout = 5000')`。sqflite 的 `execute` 在 Android 上
落到 `SQLiteDatabase.execSQL`，而 **Android 14（API 34）起 execSQL 会拒绝"可能返回
结果集"的语句**（PRAGMA / SELECT / EXPLAIN），抛的正是上面那句
`Queries can be performed using SQLiteDatabase query or rawQuery methods only.`。
`code 0 SQLITE_OK` 是 sqflite 包装时的假码，看着像"成功"，实际是 Java 层抛的。

它发生在 `onConfigure`，所以：开库整体失败 → `main()` 里 `runApp` 之前的 await 抛异常
→ 界面从不创建 → 黑屏（v1.0.1 有诊断页，于是变成可读文本）。**不是挂起、不是迁移、
不是脏数据、不是签名。** 迁移代码根本没跑到。

**修法（v1.0.2）**：

```dart
static Future<void> _applyPragmas(Database db) async {
  const List<String> pragmas = <String>['PRAGMA busy_timeout = 5000'];
  for (final String sql in pragmas) {
    try {
      await db.rawQuery(sql);          // PRAGMA 一律 rawQuery，永不 execute
    } catch (error) {
      developer.log('PRAGMA 未生效，继续启动：$sql', name: 'AppDatabase', error: error);
    }
  }
}
```

两条一起改才算修好：**换 API**（PRAGMA 走 `rawQuery`）+ **吞异常**（一条性能调优语句
不该有能力拦住启动；失败就退回默认 busy_timeout=0，功能不受影响）。

**为什么测试没抓到**：数据层测试跑的是 `sqflite_common_ffi`，不经过 Java 的 execSQL，
`execute('PRAGMA ...')` 在 ffi 上照样"成功"。所以补了两道**静态**门禁：

| 门禁 | 位置 | 挡什么 |
|---|---|---|
| `test/data/app_database_test.dart` | `flutter test test/data/` | 源码里出现 `execute('PRAGMA` 就红 + 断言 busy_timeout 真为 5000 |
| `preflight.sh` 第 4b 节 | CI 打包前 | `grep -E "\.execute\(\s*['\"](PRAGMA\|SELECT\|EXPLAIN)" lib/` 有命中就红 |

**顺手补的第 4c 节**：`pubspec.yaml` 的 `version:` 与 gradle 的 `versionCode/versionName`
必须一致——这次就发现 pubspec 还停在 `1.0.0+1` 而 gradle 已经 `1.0.1/2`，
不一致的后果是"装了新包但看不出是新包"，以后排查会更费。

**教训**：
- `onConfigure` / `onOpen` 这种开库钩子里，**只许写不会失败的东西**；PRAGMA、索引优化、
  版本自检一律 try/catch 包住，失败继续。开库钩子抛异常 = 整个 App 起不来。
- 写库语句的规矩：`execute` 只跑没有结果集的 DDL/DML；`PRAGMA`/`SELECT`/`EXPLAIN`
  一律 `rawQuery`。Android 14 把这条从"风格问题"升级成了"启动崩溃"。
- 跨平台差异（ffi vs Android Java 层）**测不出来**，只能靠静态检查 + 真机冒烟。


## 六之七、出包通道（沙箱网络限制，下次直接用）

**现象**：`git push` 报 `GnuTLS recv error (-110)` 或
`Failed to connect to github.com port 443`（连 `info/refs` 都拿不到），
但 `https://api.github.com` 一直 200。也就是说 **git 协议这条路在沙箱里是断的，
REST API 这条路是通的**。

**解法**：`tools/api_push.py` 用 Git Data API 手工造对象：
blob（base64）→ tree（`base_tree` = 远端 tree）→ commit → `PATCH /git/refs/heads/main`。

两个必须知道的点：

1. **commit 元数据必须逐字节照抄本地 HEAD**，否则 GitHub 算出来的 sha 和本地不同，
   推完就分叉。踩过的坑：message 用 `git log --format=%B` 取会**丢掉结尾换行**，
   sha 立刻变；正确做法是 `git cat-file commit HEAD` 然后按 `\n\n` 切出原始消息体。
   脚本里现在会打印"本地 tree / 远端 tree"和"远端 commit / 本地 HEAD"做自检，
   一致才更新 ref。
2. **token 只在命令行里出现**，不写进 `.git/config`（`x-access-token:$TOKEN@...` 一次性 URL）。

**一条命令**：`bash tools/ship.sh <token>`，内部顺序是
`git push（45 秒超时）→ 失败就 api_push.py → 轮询 workflow run → 下 artifact →
落到 dist/ 与 /chat/outputs/`。token 用 classic、勾 `repo` + `workflow`。
本次实测：推送 20 秒 + 构建 4 分 10 秒，全程一次过。

## 六之八、刻度标定层（第 8 步，改之前必看）

完整设计见 `ANCHOR-PLUGIN.md`。这里只放"会害你返工"的那些。

```
lib/domain/anchor/
  anchor.dart            统一出口——data/UI 只 import 这一个文件
  anchor_models.dart     UserAnchor / DeclaredImpact / AnchorEvidence / AnchorCard + 枚举
  anchor_config.dart     系数表（先验权重、0.5 封顶、AI 折价、校验门）
  anchor_engine.dart     全部判定，纯函数，无时钟无 IO
  onboarding_flow.dart   Step 1–4 渐进引导（一次只问一件事）
  proposal_codec.dart    网页版 AI 的离线导出/导入协议
  reference_ranges.dart  7 张系统参照区间（带出处标签 + 限定语）
```

- **这一层是"先验"，不是"事实"**。它的产出永远不进 `SettlementPipeline`；
  preflight 4d 第 2 条守着这件事（结算/算法层 import anchor 就红）。
- **先验权重的唯一出口是 `AnchorEngine.priorWeightFor` / `resolve`**，两处都过
  `config.clampPrior`。`AnchorConfig.priorWeightCap = 0.5` 是硬上限，
  把单项调到 0.9 也照样被夹到 0.5（有测试）。
- **「大」在代码里是锁着的**：`checkTierChange(to: large, hasCalibratedEvidence: false)`
  返回 `large_locked`；引导流程第 3 步把「大」渲染成"需要一次实测才能选"。
  不要为了方便把它放开——那是这一层唯一不能被用户自己推翻的规则。
- **覆盖只走一条路**：`coverWithEvidence(impact, evidence)` 把 `replacedBy` 指向证据，
  之后 `resolve()` 返回 `priorStillActive: false` 且权重改用证据档位。
  证据存在但没调用 `coverWithEvidence` 时，`uiNote` 会明说"还没落账"。
- **刻度变更不追溯**：`scopeForAnchorChange(dayKey)` 决定那天用新刻度还是旧刻度，
  两边都要 `mustMarkPoint: true`（图上画竖线）。不要写"变更后重跑历史"。
- **分类在入口分流**：`subjective` 的 EXP 权重恒 0 且 `mayDeduct == false`；
  `semiObservable` 只出时间占比。别在下游用"乘个 0.1"来实现，那会漏过扣分路径。
- **AI 提案的身份**：确认前 `aiProposal`（不显示数值），确认后 `userPrior`。
  不要给 AI 建"自己的通道"——`toDeclaredImpact` 调的就是 `acceptAiProposal`，
  和手填完全同一条路。
- **没有 INTERNET 权限，也不许加**。AI 接入口是剪贴板/分享旁路：
  `buildRequestText` 出去，`decode` 回来。

数据层与 UI（第 8 步后半，改之前必看）：

```
lib/data/dao/anchor_dao.dart            4 张表的行↔模型搬运，无业务判定
lib/data/repository/anchor_repository.dart  这一层唯一写入口
lib/presentation/anchor/anchor_catalog.dart     行为库 → 刻度层的单向适配
lib/presentation/anchor/anchor_page.dart        总览（卡片 + 裁决 + 记实测）
lib/presentation/anchor/anchor_onboarding_page.dart  Step 1–4 引导
lib/presentation/anchor/anchor_proposal_page.dart   网页 AI 的导出/导入/逐条确认
lib/presentation/anchor/anchor_tier_bar.dart    四档横轴小图（空心点 vs 实心点）
```

- **`recordEvidence` 必须在一个事务里**做两件事：插证据 + 把 `replaced_by` 指过去。
  分开做会留下"有证据但先验还生效"的中间态，卡片上会同时显示两套数。
- **`declareImpact` 有 `already_calibrated` 拒绝**：已被实测覆盖的项不再接受新先验。
  两套数并存 UI 解释不了，也不该解释。
- **`saveAnchor` 只追加新的 revision**：按"库里已有几条"截断 `revisionHistory.sublist(n)`，
  重复保存不会把历史复制一遍。
- **卡片只有"刻度 + 量级"都齐了才算**：`cards()` 跳过只有 anchor 没有 impact 的项，
  否则列表里会出现"标了一半"的卡片，看起来像已完成。
- **`anchor_tier_bar.dart` 不画在主曲线上**：主曲线是五维能力值，刻度层是"这事多重"，
  两条 y 轴不是一回事，硬叠会被读成"重视程度推动能力"。
- **UI 只读 `WeightResolution`**：权重、空心/虚线、误差带全来自它；
  页面里 `(r.effectiveWeight * 100).round()` 是唯一允许的算术。
- **`AnchorCatalog` 在 presentation**，不在 domain/anchor：通用插件不该认识 28 条行为库。
  分类规则：负向/计划外 → 半可观测；正向且有 questions → 可公式化；其余 → 仅主观可辨。

## 六之九、运行日志（v1.1.1，改之前必看）

```
lib/core/log/app_log.dart      环形缓冲 800 条 + 级别 + 落盘钩子（纯 Dart，零 Flutter）
lib/services/log_service.dart  落盘（support 目录 app.log，512KB 轮转）+ 全局错误钩子 + 导出报告
lib/presentation/settings/log_page.dart  设置 → 运行日志（筛选 / 复制 / 分享 / 清空）
test/core/app_log_test.dart    9 个用例（容量、筛选、截断、钩子异常、seed）
```

- **日志先于一切**：`main()` 里 `LogService.init()` 在 `runApp` 之前，但它内部全 try/catch，
  拿不到目录就降级成内存日志。**写日志失败绝不许拦住启动**（v1.0.0 黑屏的教训：
  `runApp` 前的 await 一抛就永久黑屏）。
- **每条立即 `flushSync`**：崩溃前最后几行最值钱。为此 `_append` 用
  `openSync(mode: append) → writeStringSync → flushSync → closeSync`，
  失败一次就把 `_file` 置空，后面不再每条重试（避免卡顿）。
- **不记内容**：只记"什么操作、什么结果、什么错误"。行为明细、答案、数值都不进日志——
  日志是要被复制出去发给人的。加打点时守住这条。
- **三个钩子**：`FlutterError.onError`（保留原处理）、`PlatformDispatcher.instance.onError`、
  `runZonedGuarded`（Future 忘了 catch 的那类）。
- **启动失败页有「复制运行日志」**：`StartupFailureApp` 里两个按钮——「复制诊断」（阶段+原文）
  与「复制运行日志」（含上次运行的尾巴）。黑屏时这两样一起发最有定位价值。
- **上次运行的日志会 seed 回内存**（tag=`last`，取末 120 行），所以重启后仍然看得到崩前的结尾。
- 打点位置：`main`（启动/开库/补算/提醒/首帧）、`CaptureRepository.commit`（动作+行为码+是否重算）、
  `AnchorRepository.declareImpact`（含被拒的 code）与 `recordEvidence`（种类+置信度）。

## 六之十、v1.1.2 修的三处 UI + 通知图标（改之前先读）

用户报的问题 + 日志定位到的根因，逐条对应：

| 现象 | 根因 | 修法 |
|---|---|---|
| 27 条 `PlatformException(invalid_icon)` | release APK 里 `ic_notification` **被资源收缩删掉了**：它只在 Dart 字符串里出现，R8 看不到引用。`getIdentifier` 返回 0 | `res/raw/keep.xml`（`tools:keep`）+ `NotificationService.init` 全 try/catch + `_initFailed` 标记（失败只重试一次，不再刷屏） |
| x 轴日期叠成一坨 | painter 硬画 first/mid/last 三个标签，数据点稀疏时 mid 贴在 first 上 | `_paintAxisLabels`：量宽度、首尾优先、中间按剩余空间决定（间距 < 10px 就不画）；首尾同日只画一个 |
| 切区间"下面没跟踪" | 摘要与预测线永远用 90 天那条 `forecast`，与所选区间无关 | 预测点按 `_rangeDays` 截断（截空则退回完整列表）；图下加一行「近 N 天 · 有记录 X 天 · 预测到 M/d」 |
| FAB「记录一件事」太偏 | 默认右下角，压住正文（曲线页免责声明被盖） | `FloatingActionButtonLocation.centerFloat` |

- **通知是增强功能**：`init` 失败、`requestPermission` 失败、`scheduleDaily` 失败全部只记 warn 不抛。
  用户点"开启提醒"绝不能因为一个图标资源而崩。
- **`res/raw/keep.xml` 不能删**：删了通知图标会再次被收缩掉。打包工具看不到 Dart 字符串里的资源引用，
  这是 Android 资源收缩的经典坑，不是 Flutter 特例。

## 六之十一、自建项目（v1.1.3，改之前必看）

内置库之外的行为（「上一堂课」这类），三处分工：

```
lib/domain/models/custom_behavior.dart   CustomBehaviorRecord + customBehaviorDef()
lib/data/dao/custom_behavior_dao.dart    只搬行
lib/data/repository/custom_behavior_repository.dart  create 一个事务写三处
lib/presentation/anchor/new_behavior_page.dart       三步：说清 → AI 具体化 → 确认创建
```

- **量化不另起一套**：自定义行为的 `derive` 只产出 `doseFraction = 实际量 / 目标量`
  （>1.5 封顶），之后照旧走 `baseScoreFor → score → EXP`。所以它的分数与内置行为
  完全同一套系数，改 `BalanceConfig` 一起变。**别在这里自己算 EXP**。
- **建一次写三处**（`custom_behavior` + `user_anchor` + `declared_impact`）必须同事务，
  少写一处就得到"能记但刻度页看不到"或"库里有但记不了"的半成品。
- **注册不是重建**：`BehaviorLibrary.register()` 原地加进 `all` 与索引，
  `CaptureMachine` / `IntentMatcher` 持有同一实例，所以立刻生效。
  新建后在采集页要能匹配到 → `AppShell` 在 build 里 `ref.listen(customBehaviorsProvider)`，
  不管从哪个入口新建都会注册；`_openCapture` 前再 `_loadCustom()` 兜一次。
- **AI 只给形状，不给分数**：`NewBehaviorCodec` 的三档封顶、缺 citation 降档、
  自造数字打回、`target_dose > 0` 必填，与刻度层同一套纪律。确认后先验身份是
  `userPrior`（拍板的是人）。
- **`target_dose` 是分母**：预览页允许用户改这两个数（AI 常把"一次"定得过大或过小），
  改完以用户为准。

## 六之十二、release 关了 R8 / 资源压缩（v1.1.3）

`android/app/build.gradle.kts` 的 release 里 `isMinifyEnabled = false` +
`isShrinkResources = false`。两个真实事故都出在这里：

| 版本 | 现象 | 根因 |
|---|---|---|
| v1.1.1 | `PlatformException(invalid_icon)` × 27 | `ic_notification` 只在 Dart 字符串里被引用，资源收缩器看不到 → 从 APK 删掉 |
| v1.1.2 | `PlatformException(error, Missing type parameter)` | FLN 用 Gson 反序列化已保存排程，R8 擦掉泛型 `Signature` |

自用分发不为几 MB 维护 keep 规则。**将来若要开回来**：加 `proguard-rules.pro`
保留 `com.dexterous.**`、`com.google.gson.**` 与 `-keepattributes Signature,*Annotation*`，
并保留 `res/raw/keep.xml`（它已经在仓库里）。

## 六之十三、日志纪律：不记内容 + 上次运行单独分节（v1.1.4）

两条规则，都是踩出来的：

1. **日志里不许出现用户输入的自由文本。**
   起因：`logInfo('custom', '生成新项目提示词 射了')` 把项目名写进了日志，
   而日志是要被复制出去发人的。现在只记动作与结构字段
   （`nameLen`、`code`、`axis`、`tier`），内置行为的 `code` 可以记
   （它是固定公开字符串），**自建项目的名字不记**。
   加打点时自查三件事：会不会带出行为内容？会不会带出数值？会不会带出用户自由文本？
2. **上次运行的日志默认不混进本次。**
   `LogEntry.previousRun = true`，`snapshot()` / `dump()` 默认排除，
   `errorCount` 只数本次。导出报告里单独一节「上次运行的最后 25 行」。
   起因：日志导出的前半截全是上次的碎片，时间戳被压成"现在"，
   128 条里 119 条是 `[last]`，真正有用的本次时间线被埋了。

## 六之十四、量化形状（Quant Layer）· 第一刀已落，设计见 `QUANT-PLUGIN.md`

**问题**：自建项目能建了，但影响一律走 `实际量 / 目标量` 这条直线，
且只能挂在 5 个内置维度之一。「一次看电影」和「一次刷题」同一条曲线；
「陪伴」被迫记成 `discipline`。用户问的是：能不能让 AI 顺便给出**量化方式**，
并在 App 里长出**新的维度与曲线**。

**结论**：能，但要拆成三件不同的事，各有各的容器：

| 层 | 内容 | 状态 |
|---|---|---|
| 量化形状 | 四种形状（linear / log / saturating / threshold），**归一化到「目标量 = 1.0」** | v1.2.0 第一刀已写 |
| 自建维度 | `ability`（进主曲线，必须有衰减依据）/ `experience`（只记频次与主观分，EXP 恒 0） | v1.2.1 |
| 体验曲线 | 周频次 + 主观分均值与误差带，**不进主曲线** | v1.2.2 |

- **形状不另起一套公式**：它只决定 `doseFraction` 的映射，`baseScoreFor` /
  质量加成 / 效率加成 / 状态乘数 / 置信权重一个字不改。目标量处恒为 1，
  所以满分线不随形状漂。
- **尺度不变是硬约束**：对数支的 `k` 无色纲，作用在 `d/T` 上。
  写成 `ln(1+k·d)/ln(1+k·T)` 时 `d=T` 也是 1，但目标量 40 做一半得 0.82、
  目标量 1 得 0.585 —— 用户改个目标量就悄悄换了形状。已修，测试守着
  （同比例 × 4 种量级结果必须一致）。
- **AI 只选形状 + 档位参数**：`k ∈ {0.5,1,2,4}`、`θ ∈ {T, 0.5T}`，其余整条打回
  （`R_FREE_PARAM`）。不让 AI 输出公式或裸系数，是这一层可核对性的全部来源。
- **`biphasic` 故意不做**：负向已有独立 category + `negativeCurve`，
  一个形状同时产出正负会破「负向不乘状态乘数」。
- **新维度落库不需要 DDL**：`ability_snapshot.abilities_json` 是 JSON map、
  `forecast_point.axis` 是 TEXT。真正卡住的是代码里 8 处
  `for (final axis in ProjectAxis.values)`。
- **轴权重仍是系数不是数据**：用户轴权重进 `BalanceConfig.axisWeightOf(String)`，
  走 `configOverride` 覆盖；写进表里会绕过重算通道，破铁律 5。
- **`ProjectAxis.parse` 的静默回退是现存 bug**：未知轴一律变 `strength`，
  一旦有自定义轴，会把「陪伴」记进体能且不报错。v1.2.1 改 `tryParse` + `unknown` 轴。
- **多轴分摊（一条记录拆多条事件）首版不做**：`valence_event` 唯一约束
  `(day_key, behavior_code, slot_key)` 要么改（红线）、要么给 `slot_key` 加轴后缀
  （重算与归因全要重审）。首版只支持「一个主维度 + 若干体验维度」。

**数据层已接（v1.2.0 第二步，schema 5）**：

```
lib/data/db/schema.dart      Tables.behaviorQuantSpec / Tables.axisDefinition + kQuantTables（2 表 + 1 索引）
lib/data/db/migrations.dart  version 5；v4 → v5 只跑 kQuantTables（IF NOT EXISTS，重复升级不炸）
lib/data/dao/quant_dao.dart  行↔模型；upsert 先读 created_at/revision 再 replace（minSdk 23 的 SQLite 没 upsert 语法）
lib/data/repository/quant_repository.dart  唯一写入口：四道闸在前，写库在后；删维度前先查有没有口径在用它
lib/data/repository/custom_behavior_repository.dart  create 事务里多写一条 linear 基线；remove 一起删
```

- **两条 CHECK 是库层的硬约束**：`target_dose > 0`、`shape_kind` 四选一、
  `dim_kind` 两选一且 `ability` 必须 `decay_tau_days > 0`。
  `schema_check.py` 用真 SQLite 逐条验证它们会拒绝（不是靠代码自觉）。
- **`axis_definition` 没有 `default_weight` 列**：轴权重是系数，必须住 `BalanceConfig`
  （`axisWeight.<key>` 走 configOverride）。放进表就能绕过重算通道，铁律 5 当场破。
- **建项目的基线口径与 v1.1.3 逐字等价**（那时 `derive` 里就是 `实际量 / 目标量`），
  所以口径开始入库、分数一点没变；下一步 `derive` 改读它，同样的记录仍得同样的分。
- **老 DDL 零改动**：`git diff lib/data/db/schema.dart` 的删除行是 0。
- 新增测试：`test/data/quant_dao_test.dart`（19）+ `quant_repository_test.dart`（12），
  含"在已 v5 的库上重跑 v4→v5 不炸"与"从 v1 兜底升级"两条迁移幂等用例。

本轮 domain 新增（纯增量，**既有 lib 文件未被改写**，无人 import，行为零变化）：

```
lib/domain/quant/quant.dart            统一出口（上层只 import 这个）
lib/domain/quant/dose_shape.dart       四种形状 + 参数白名单 + 尺度不变
lib/domain/quant/axis_registry.dart    AxisSpec / AxisKind / AxisRegistry（unknown 不回退 strength）
lib/domain/quant/quant_measure.dart    MeasureKind + ImpactShare（量什么 / 落在哪）
lib/domain/quant/quant_spec.dart       QuantSpec（折算唯一出口 doseFractionFor）
lib/domain/quant/quant_validate.dart   四道闸 + 份额归一 + 新维度降级
lib/domain/quant/quant_request.dart    导出端：给网页 AI 的请求文本
lib/domain/quant/quant_response.dart   导入端：解析 + 自带 extractJson（不 import anchor）
lib/domain/models/custom_behavior.dart     记录（数据）
lib/domain/models/custom_behavior_def.dart 适配器（数据 → BehaviorDef）
lib/presentation/quant/shape_picker.dart   四选一控件（新建页 / 将来的口径页共用）
test/quant/*.dart                     5 文件 / 92 个 test
```

**这一轮还做了一次切割**（不是重构洁癖，是为了不让 import 关系骗人）：

- `quant_spec.dart` 447 行 → `quant_measure` / `quant_spec` / `quant_validate` 三份。
  一个文件里塞"输入形状 + 规格 + 四道闸"会让人以为校验和折算是一层；
  实际上一份是数据、一份是算式、一份是守卫。
- `quant_codec.dart` 406 行 → `quant_request` / `quant_response`。
  导出失败（文本没说清）与导入失败（AI 回复不合规）是两类问题，混在一起排查会串味。
- `custom_behavior.dart` → 记录留原处，`linearBaselineFor` / `customBehaviorDef`
  切到 `custom_behavior_def.dart`。好处很实在：**模型文件不再 import quant 层**，
  "数据" 与 "适配器" 在 import 图上分开了。
- `new_behavior_page.dart` 里的 `_shapePicker()` → `presentation/quant/shape_picker.dart`。
  口径编辑页要用同一个控件，两处各写一遍必然得到两种措辞。

- **边界守卫已加**（`tools/preflight.sh` 4e 四条 + 4f 一条 API 清单）：quant 层零 Flutter/data 依赖、
  结算/算法层不许反向 import quant（接线只许走 `lib/domain/models`）、
  quant 层不许出现 `expPerPoint|applyExp|totalExp|SettlementPipeline`、quant 与 anchor 互不依赖；
  **4f** 列了 17 个公开声明，切文件时掉一个就红——因为 `parse_dart` 只查语法、
  `check_symbols` 只查类型 import，整段丢函数它们都看不出来（刚踩过）。
- **`test/quant/` 已进 CI**（`.github/workflows/build-apk.yml` 第 81 行）。
  这是故意的：仓库那 6 个红测试就是因为从没在 CI 上跑过（七之六）。
  第一次跑红就拿真实报错回来修，不许删断言。
- 静态验收：`parse_dart.py` 164 文件 0 错 / `check_symbols.py` 400 符号无缺失 /
  preflight 4d + 4e 全绿（另三处 ✗ 是沙箱无 SDK 的既有状态）。
- **顺手修的一处真 bug**：`create(quant:)` 原来用默认注册表（只有内置 5 维）校验，
  口径挂在用户自建维度上时会被 `T_AXIS_DEMOTED` 静默降成体验维度——分数当场消失。
  现在先用 `_quant.axes(_db)` 把真注册表读出来再判，有回归测试。
**分水岭已过（v1.2.0 第三步，用户侧可见）**：

```
custom_behavior.dart   customBehaviorDef(r, {QuantSpec? quant})
                       + linearBaselineFor(r)（唯一基线定义处）
                       derive 里 fraction = spec.doseFractionFor(dose)，不再自己除
behavior_library.dart  replace(defs)：同名 code 原地换定义（register 会跳过，口径改不掉）
app_shell.dart         _syncCustom()：项目 + 口径一起进行为库；口径读失败退回线性
providers.dart         quantRepositoryProvider + customQuantSpecsProvider
new_behavior_page.dart 预览页新增「怎么折算」四选一，选的形状随 create() 落库
repository.create()    可选 quant 参数；**先校验再写**，k=0.37 这种退回线性并记 warn
```

- **`register` vs `replace` 是真坑**：`register` 跳过已存在 code，所以"口径从线性改成
  对数"在旧路径下**永远不会生效**（行为码没变）。`replace` 专治这个，测试里两种都断言了。
- **没口径行的老项目行为不变**：`quant == null` → `linearBaselineFor` → 与 v1.1.x 逐字等价。
- **目标量只有一个真源**：`create()` 用 `forBehavior(code, targetDose: record.targetDose)`
  把用户改过的目标量写进口径，`BehaviorDef.targetDose` 也从口径取。
  **将来做编辑功能时必须同时改口径的 target_dose**，否则提问范围与折算分母会对不上。
- **UI 只给形状不给系数**：六种组合里对数固定 k=1、阈值固定 1 倍目标量。
  新建时让人填 k 是拿准确性换不必要的复杂度。
- 新增测试：`test/quant/custom_behavior_quant_test.dart`（11）+ 仓储测试里 3 条
  （改口径后 derive 从 0.5 变 0.631、手选事件型落库、自由参数退回线性）。
**v1.2.1：项目能改了（旧账 ② 结清）**

```
repository.update()      同事务改 custom_behavior + behavior_quant_spec；
                         `_resolvedSpec` 三级回退：新口径（过闸）→ 库里旧口径（rebase 到新目标量）→ linear 基线
presentation/anchor/custom_behavior_page.dart  列表 + 编辑（名字/目标量/单位/折算方式）+ 删除
anchor_page              「管理自建项目」入口
```

- **只改名字不碰口径**：`quantTouched` 判断，避免改错别字也把 revision 顶上去
  （「改过几次口径」要查得清）。
- **编辑保留原维度归属**：`_EditSheet` 沿用 `spec.impact`，不顺手把"算哪个维度"改成内置默认。
- **行为码永不改**：改名只改 name/description，改 code 就等于丢历史（幂等键里有它）。
- 测试：`test/data/custom_behavior_update_test.dart` 7 条（两真源同步、只改名、
  空名不改、坏参数保留旧口径、不存在返回 null、revision 递增）。
- **还没做的**：维度注册表接管 `ProjectAxis.values`（v1.2.2）、体验曲线与主图维度选择器
  （v1.2.3）。
- **v5 迁移还没在真机上跑过**（沙箱只有 ffi）。下次装机第一件事：
  能进首页 = 迁移通过；若停在启动失败页且阶段是「迁移」，把原文回传——
  v5 只跑两条 CREATE + 一条 CREATE INDEX，全部 IF NOT EXISTS，最可能的失败是
  CHECK 写法在设备 SQLite（3.8 × minSdk 23）上不被接受，`schema_check.py` 用的是
  桌面 SQLite，版本差异测不出来。

## 七之六、既有红测试：6 个（2026-11-13 首跑全量才暴露）

CI 一直只跑 `flutter test test/data/`，所以 `test/engine` 与 `test/capture` 里的这些
**从来没在 CI 上执行过**。第 8 步改成跑 `test/data/ test/anchor/` 之后，剩下的债在这里记账。
**处理原则：先判「代码对还是测试期望对」，不许为了绿去改期望值。**

| 测试 | 期望 | 实际 | 初判 |
|---|---|---|---|
| engine/valence_engine 「负向先扣缓冲池，不动总经验」 | 总经验 190 | 200 | 负向没从缓冲池扣，或缓冲池比例与测试设定的 10 点不一致 |
| capture/state_machine 「主动回忆 20 词，3 天保持率约 68%」 | 0.68 | 0.5115 | 遗忘曲线参数（`memoryStrengthBase` / `reviewBoost`）与测试预设的稳定度不匹配 |
| capture/state_machine 「只看一遍的保持率显著更低」 | > 0.5115 | 0.5115 | 两条路径算出同一个值 —— 主动回忆加成没进公式 |
| capture/state_machine 「02:10 入睡，熬夜分钟」 | 110 | 100 | 熬夜越界分钟的起点（睡眠线 00:20）少算 10 分钟 |
| capture/state_machine 「回执点『改一下』回到第一题，答案仍在」 | 20.0 | `'new'` | 回执阶段回退把答案清成了首项默认值 |
| capture/state_machine 「上一步回退一道题并清掉该题答案」 | `words` | `method` | 回退步数与测试预期错位一道 |

这 6 条在 v1.0.0–v1.0.2 期间一直存在，只是没跑过。**不影响装机使用**（它们在 domain 算法细节，
不是崩溃路径），但说明"引擎行为"和"我们以为的引擎行为"有 6 处没对齐。单独一版处理。

## 七、已知待办与坑

- **Android 14+ 的 execSQL 拒绝 PRAGMA/SELECT**（v1.0.2 的事故根因，详见六之六）：
  写库语句里 `execute` 只能跑 DDL/DML，查询类一律 `rawQuery`；开库钩子里的语句
  必须 try/catch。代价是黑屏整整一个版本。
- **口径与项目的目标量必须同步改**：`behavior_quant_spec.target_dose` 是折算分母，
  `custom_behavior.target_dose` 是提问范围。做编辑功能时两处一起改（同事务），
  否则"改了目标量但曲线没变"会成为一个很难查的现象。
- `foreign_keys` 目前在 Android 上**没有显式打开**，而 `tools/schema_check.py` 是打开后
  验 DDL 的、级联删除也确实依赖 FK。要在 `_applyPragmas` 里加
  `PRAGMA foreign_keys = ON` 必须先确认每个仓储的删除顺序都靠 CASCADE 而不是靠"手删子表"，
  否则会引入新的 ForeignKeyViolation。**别顺手加**，单独一版做，配 DeletingOrder 测试。
- `android/gradle/wrapper/gradle-wrapper.jar` 还是没有（沙箱生成不了二进制），
  CI 用 `flutter create` 现场补 —— 见七之四那张失败表第 1 行。
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

## 七之补、当前卡点（新对话第一眼要看）

1. **v1.1.0 已出包，等装机验证**：装 `dist/exp-ledger-1.1.0.apk`（覆盖安装，签名没换）。
   冒烟顺序：设置页 →「刻度标定」→ 挑 3 项 → 逐项定单位 → 声明量级 → 保存 →
   回列表看卡片（先验标签 + 四档小图空心点）→ 记一次实测 → 看文案是否变成
   「你当初估的是…实测接近…」→ 退出重进看还在。
   若某一步白屏/报错，先看 `flutter test` 有没有覆盖到的那块（domain 有 4 个测试文件），
   再回 `AnchorEngine` 的四个门排查。
2. **启动崩溃已确诊并修好**（v1.0.2：PRAGMA 改 rawQuery + 吞异常，见六之六）。
   待办只剩"装机验证"：装 v1.0.2 →
   - 能进首页 = 修对了；
   - 若仍停在诊断页，**先看阶段**：`打开数据库` = 还有第二条开库语句中招；
     `迁移` = 迁移里某条 DDL 在设备 SQLite 上不被接受（把文本回传即可）；
3. **签名已固定**（`android/app/debug.keystore`），v1.0.1 → v1.0.2 可覆盖安装，不用卸载。
4. 产物已出：`dist/exp-ledger-1.0.2.apk`（sha256 `886f02af…`，CI run 43293073012）。
   出包通道见六之七——**沙箱里 `git push` 走不通，必须用 `tools/ship.sh`**。
5. 装机冒烟清单（v1.0.2 一次性走完，别再分版本）：
   记录一条 → 杀进程重开看还在 → 提醒设到 2 分钟后等响 → 加桌面小组件看数字 →
   导出看分享面板 → 设置里"重算"一次看曲线是否变。

## 八、续接提示词（新会话直接粘这段）

> 继续做经验账本项目。先读 `/workspace/exp_ledger/STATE.md`（进度、铁律、数据层/刻度层/
> 自建项目/日志四节的结构与坑），细节读 `ANCHOR-PLUGIN.md`。
>
> 现状：v1.1.4 已出包并装机验证过。第 1–12 步全部完成：
> 刻度标定层（先验 ≤0.5、大档锁定、实测覆盖、网页 AI 离线提案）、
> 自建项目（内置库没有的行为就地新建，AI 给形状、公式算分）、
> 运行日志（环形缓冲 + 落盘 + 全局钩子 + 不记内容 + 上次运行分节）。
> 最新产物 `dist/exp-ledger-1.1.4.apk`（sha256 见上），CI 跑
> `test/data/ test/anchor/ test/core/` 三组。
>
> 已知欠账（按建议顺序）：
> ① 既有 6 个红测试（STATE 七之六有期望/实际/初判三栏）——先判"代码对还是测试期望对"，
>    不许为了让 CI 变绿去改期望值；
> ② ✅ 已结清（v1.2.1）：自建项目可编辑/删除，`update()` 同事务改两个真源；
> ③ 饮食采集入口没做，`EnergyLedger.intakeKcal` 恒为 0；
> ④ `PRAGMA foreign_keys = ON` 没开（要先审删除顺序，配 DeletingOrder 测试）；
> ⑤ 刻度图（AnchorTierBar）只在刻度页用，明细页还没显示"这条是先验"。
> ⑥ 量化形状层（`QUANT-PLUGIN.md`）：domain 5 文件 + 测试 4 文件（81 test，已进 CI）
>    + v5 迁移两张表（`behavior_quant_spec` / `axis_definition`）+ DAO/仓储
>    + 自建项目创建时写 linear 基线，全部已落；preflight 4e 四条守卫。
>    **分水岭已过**：`derive` 已改成读库里口径（linear 时结果完全相同）、
>    新建页预览已有「怎么折算」四选一、`BehaviorLibrary.replace` 让口径改得掉。
>    剩下 v1.2.1 维度注册表接管 `ProjectAxis.values`、v1.2.2 体验曲线与主图维度选择器；
>    以及"口径独立编辑页"（现在只能在建项目时选一次形状）。
>    注意：`quant` 不许被 engine/settlement import，接线口只有 `lib/domain/models`；
>    轴权重永远住 `BalanceConfig`，不许落表。
>
> 三条红线：不加 INTERNET 权限（AI 全走剪贴板旁路）；
> 结算/算法层不许 import anchor（preflight 4d 会红）；既有 17 张表的 DDL 一条不改。
> release 现在关了 R8/资源压缩（六之十二），不要再打开，除非补 proguard 规则。

## 九、交付给用户时的语气约定

- 中文回复，直接、具体、可操作。
- 科学公式一律标注出处 + 误差 + 是否简化；无法确证的标"待核实"，绝不编。
- ACWR / sRPE 必须写明"竞技体育外推，非普通人群诊断"。
- 涉及损伤风险必须给就医指引，App 不下诊断。
- 负向文案中性，不羞辱、不红色警报、不断签清零、无排行榜。
