# 第 7 步 · 构建打包

> 结论先说：**这台沙箱产不出 APK**，原因不是缺 SDK，是架构。
> 下面给出三条能真正拿到 APK 的路，以及一份按概率排序的报错预案。

## 1. 为什么这里产不出

沙箱是 `aarch64` + PRoot（Ubuntu 24.04）。要产 APK 需要这些 native 二进制：

| 工具 | 用途 | 官方 linux 构建 |
|---|---|---|
| `aapt2` | 编资源、打包 | 只有 **x86_64** |
| `zipalign` | 对齐优化 | 只有 **x86_64** |
| `d8` / `r8` | dex 转换 | JVM（可跨架构） |
| `apksigner` | 签名 | JVM（可跨架构） |
| `gen_snapshot` | AOT 编译 Dart | 随 Flutter host 架构 |

`aapt2` 和 `zipalign` 是硬阻塞：`./aapt2: cannot execute binary file: Exec format error`。
本机没有 qemu-user / box64，PRoot 下装 binfmt 转译也不现实（构建一轮要几十分钟）。

JDK 17 是有的（`openjdk 17.0.21`），Flutter / Android SDK / Gradle 都没有。
网络能到 `storage.googleapis.com`（Flutter 下载源通），但下完也跑不了 `aapt2`。

**所以不假装产出 APK。** 下面是三条真能出包的路。

## 2. 路 A：推 GitHub，CI 出包（最省事）

仓库里已经放好 `.github/workflows/build-apk.yml`。推到 GitHub 后：

1. 仓库 → Actions → `build-apk` → Run workflow（或直接 push 到 main）；
2. 等约 6–10 分钟；
3. 在 run 页面底部下载 `exp-ledger-apk`，里面是 `app-release.apk`；
4. `adb install -r app-release.apk`，或传到手机点装（需允许未知来源）。

CI 里跑的顺序就是本地要跑的顺序，任何一步报错都会停在第几步，日志能直接对应下面第 4 节的条目。

## 3. 路 B：本地 x64 机器（有 Flutter 环境）

```bash
# 0. 先备份手写的 android/，flutter create 可能补文件也可能覆盖
cp -r android android.bak

# 1. 补 gradle wrapper jar / local.properties（缺了就构建不了）
flutter create --platforms=android .

# 2. 确认它没动你手写的东西
diff -r android.bak android | head -50

# 3. 预检 + 一键构建
bash tools/preflight.sh
bash tools/build_apk.sh          # 或 --debug
```

如果第 2 步发现 `AndroidManifest.xml`、`MainActivity.kt`、`ledger_widget.xml`
被覆盖，把备份里的版本覆盖回去再构建；`gradle-wrapper.jar`、`local.properties`、
`.gitignore` 这几个留着新的。

## 4. 预计报错与修法（按概率排序）

1. **`Could not find or load main class org.gradle.wrapper.GradleWrapperMain`**
   → 缺 `gradle-wrapper.jar`。跑 `flutter create --platforms=android .` 补。

2. **`aapt2: cannot execute binary file`**
   → 你在 arm64 机器上构建。换 x64，或用路 A。

3. **`undefined_identifier: Ref` / `FutureProviderRef`**
   → Riverpod 2.5 的 `Ref` 是无泛型基类。所有 provider 回调都写成不标注参数类型
   （`(ref) => ...`），让上下文推断。若 analyze 仍报，把显式 `Ref ref` 改成无类型。

4. **`The argument type '({double value, bool reset})?' can't be assigned...`**
   → `showModalBottomSheet` 的 record 泛型。确认 SDK `>=3.5.0`，且
   `_ConfigEditorSheet` 的 `Navigator.pop` 传的是同结构的 record 字面量。

5. **`PathMetric isn't a type`**
   → `dart:ui` 的导出范围随版本变。已显式 `import 'dart:ui' show PathMetric;`；
   若仍报，改成 `import 'dart:ui' as ui;` + `ui.PathMetric`。

6. **`The method 'requestNotificationsPermission' isn't defined`**
   → 你的 `flutter_local_notifications` 低于 17。检查 `flutter pub deps | grep notifications`。

7. **`R.layout.ledger_widget` 未解析（Kotlin 编译期）**
   → `namespace` 与 Kotlin `package` 不一致。`tools/preflight.sh` 第 3 节会先查。

8. **`uses-sdk:minSdkVersion 23 cannot be smaller than version 24`**
   → 某个依赖抬高了 minSdk。看报错里点名的库，把 `minSdk` 抬到它要求的值
   （`flutter_local_notifications` 17 要 21+，`sqflite` 21+，一般 23 够）。

9. **`Execution failed for task ':app:lintVitalRelease'`**
   → release 构建会跑 lint。先看具体 lint 项；临时可 `flutter build apk --debug` 验证功能。

10. **运行时白屏、`StateError: appDatabaseProvider 没有注入`**
    → `main()` 里的 `ProviderScope(overrides: ...)` 被改掉了。检查 `main.dart`。

11. **桌面小组件不刷新**
    → `AndroidManifest.xml` 里 `LedgerWidgetProvider` 的 receiver 或
    `appwidget-provider` meta-data 丢了；或 `todayProvider` 从未成功加载
    （小组件数据只在 Dart 侧算好后才推）。

## 5. 装机验收（五个动作，缺一不可）

1. **记一条** → 首页净 EXP 立刻变，明细页能看到算式；
2. **杀进程重开** → 那条记录还在（验证 SQLite + 幂等键，不是内存）；
3. **同一天同一行为再记一次** → 不新增第二条，而是 `revision 1`（验证覆盖而非累加）；
4. **打开提醒，等它响** → 文案里没有"你已 3 天没记录"这类话；
5. **桌面加小组件** → 数字与首页一致；再从明细改一条记录，回桌面看是否跟着变。

导出顺手验一下：设置 → 导出 → 系统分享面板能弹出，文件是合法 JSON。

## 6. 产物与签名

- 产物：`build/app/outputs/flutter-apk/app-release.apk`
- 当前 `release` 用的是 **debug 签名**（`signingConfig = debug`），自己装机没问题；
  真要分发得换自己的 keystore：

```bash
keytool -genkey -v -keystore ~/exp-ledger.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias exp-ledger
```

然后把 `android/key.properties`（不要提交）与 `signingConfigs` 接到
`app/build.gradle.kts` 里，把 `release` 指向它。

## 7. 依赖清单（版本矩阵）

| 组件 | 版本 | 备注 |
|---|---|---|
| Dart SDK | >= 3.5.0 | record / 增强枚举 |
| Flutter | 3.24.x | CI 固定 3.24.5 |
| AGP | 8.3.2 | 需要 JDK 17 |
| Gradle | 8.7 | wrapper 指向 8.7-all |
| Kotlin | 1.9.22 | jvmTarget 17 |
| compileSdk / targetSdk | 34 | |
| minSdk | 23 | 依赖下限 21 |

Dart 依赖：`flutter_riverpod ^2.5.1`、`sqflite ^2.3.3`、
`flutter_local_notifications ^17.2.1`、`timezone ^0.9.2`、`share_plus ^9.0.0`、
`path_provider ^2.1.3`、`path ^1.9.0`、`fl_chart ^0.68.0`、`intl ^0.19.0`。
测试侧：`sqflite_common_ffi ^2.3.3`。
