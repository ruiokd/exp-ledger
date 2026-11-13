#!/usr/bin/env bash
# 构建前预检：把能在本地发现的问题先发现掉，别等 Gradle 跑到一半才报。
#
# 用法：bash tools/preflight.sh
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
note() { printf '  %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=1; }

echo "== 1. 工具链 =="
if command -v flutter >/dev/null 2>&1; then
  ok "flutter: $(flutter --version 2>/dev/null | head -1)"
else
  bad "没有 flutter（需要 3.24+）"
fi

if command -v java >/dev/null 2>&1; then
  JV=$(java -version 2>&1 | head -1)
  ok "java: $JV"
  case "$JV" in
    *\"17*) ;;
    *) note "注意：Android Gradle Plugin 8.3 需要 JDK 17" ;;
  esac
else
  bad "没有 java（需要 JDK 17）"
fi

if [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; then
  ok "Android SDK: ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
else
  bad "ANDROID_HOME / ANDROID_SDK_ROOT 都没设"
fi

echo "== 2. Android 工程完整性 =="
for f in \
  android/settings.gradle.kts \
  android/build.gradle.kts \
  android/app/build.gradle.kts \
  android/app/src/main/AndroidManifest.xml \
  android/app/src/main/kotlin/com/yg/ledger/MainActivity.kt \
  android/app/src/main/kotlin/com/yg/ledger/LedgerWidgetProvider.kt \
  android/app/src/main/res/layout/ledger_widget.xml \
  android/app/src/main/res/xml/ledger_widget_info.xml \
  android/app/src/main/res/drawable/ic_notification.xml
do
  [ -f "$f" ] || bad "缺文件：$f"
done

if [ -f android/gradle/wrapper/gradle-wrapper.jar ]; then
  ok "gradle wrapper jar 在"
else
  bad "缺 android/gradle/wrapper/gradle-wrapper.jar —— 先备份 android/，再跑 flutter create --platforms=android ."
fi

echo "== 3. 包名一致性 =="
NS=$(grep -o 'namespace = "[^"]*"' android/app/build.gradle.kts | cut -d'"' -f2)
APPID=$(grep -o 'applicationId = "[^"]*"' android/app/build.gradle.kts | cut -d'"' -f2)
PKG=$(head -1 android/app/src/main/kotlin/com/yg/ledger/MainActivity.kt | sed 's/package //')
note "namespace=$NS applicationId=$APPID kotlin package=$PKG"
if [ "$NS" = "$APPID" ] && [ "$NS" = "$PKG" ]; then ok "三处一致"; else bad "三处不一致，R 类会找不到"; fi

echo "== 4. 静态检查（不需要 Dart SDK 的那部分）=="
if command -v python3 >/dev/null 2>&1; then
  python3 tools/check_symbols.py || FAIL=1
  python3 tools/schema_check.py >/dev/null && ok "DDL 验收通过" || bad "DDL 验收失败"
  if python3 -c "import tree_sitter_dart" 2>/dev/null; then
    python3 tools/parse_dart.py || FAIL=1
  else
    note "没装 tree_sitter（pip install tree_sitter tree_sitter_dart），跳过语法树解析"
  fi
else
  note "没有 python3，跳过静态检查"
fi

echo "== 4b. Android 14 兼容：PRAGMA 不许走 execute =="
# Android 14（API 34）起 SQLiteDatabase.execSQL 拒绝"可能返回结果集"的语句
# （PRAGMA / SELECT / EXPLAIN），抛
#   Queries can be performed using SQLiteDatabase query or rawQuery methods only.
# 在 onConfigure 里中招就是启动黑屏。这条在 ffi 测试里复现不了，只能静态查。
PRAGMA_HITS=$(grep -rn --include='*.dart' -E "\.execute\(\s*['\"](PRAGMA|SELECT|EXPLAIN)" lib/ 2>/dev/null)
if [ -n "$PRAGMA_HITS" ]; then
  bad "execute() 跑了 PRAGMA/SELECT（Android 14 会抛异常），改成 rawQuery："
  printf '%s\n' "$PRAGMA_HITS"
else
  ok "没有 execute() 跑 PRAGMA/SELECT"
fi

echo "== 4c. 版本号一致性（pubspec ↔ gradle）=="
PUB_VER=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
PUB_NAME=${PUB_VER%%+*}
PUB_CODE=${PUB_VER##*+}
GRD_NAME=$(grep -o 'versionName = "[^"]*"' android/app/build.gradle.kts | cut -d'"' -f2)
GRD_CODE=$(grep -o 'versionCode = [0-9]*' android/app/build.gradle.kts | awk '{print $3}')
note "pubspec=$PUB_VER gradle=$GRD_NAME+$GRD_CODE"
if [ "$PUB_NAME" = "$GRD_NAME" ] && [ "$PUB_CODE" = "$GRD_CODE" ]; then
  ok "版本号一致"
else
  bad "版本号不一致：两处都要改，否则装上去看不出是新包"
fi

echo "== 4d. 刻度标定层（anchor）的边界守卫 =="
# 这一层是后加的插件。它一旦被结算流水线 import，就说明"先验"和"事实"混了：
#   - anchor 层只许依赖 dart: 与 lib/domain/enums.dart（纯函数，可脱机测试）
#   - 结算/算法/采集/预测不许反向依赖它（否则改先验会重算历史 EXP）
#   - 它不许直接碰 daily_log（写库唯一通道仍是 CaptureRepository.commit）
ANCHOR_LAYER_LEAK=$(grep -rn --include='*.dart' -E "package:(flutter|sqflite|share_plus)|exp_ledger/(data|presentation|services)" lib/domain/anchor/ 2>/dev/null)
if [ -n "$ANCHOR_LAYER_LEAK" ]; then
  bad "anchor 层引入了不该有的依赖（必须保持零 Flutter / 零 data 依赖）："
  printf '%s\n' "$ANCHOR_LAYER_LEAK"
else
  ok "anchor 层只依赖 dart: 与 domain/enums.dart"
fi
ANCHOR_REVERSE_DEP=$(grep -rn --include='*.dart' "domain/anchor" lib/domain/engine lib/domain/settlement lib/domain/science lib/domain/behaviors lib/domain/capture lib/domain/forecast 2>/dev/null)
if [ -n "$ANCHOR_REVERSE_DEP" ]; then
  bad "结算/算法层反向依赖了 anchor（先验会污染事实账）："
  printf '%s\n' "$ANCHOR_REVERSE_DEP"
else
  ok "结算/算法层没有反向依赖 anchor"
fi
# 注释行里出现表名是允许的（那是在写"本层不碰它"的说明），只拦真代码。
ANCHOR_WRITES_LOG=$(grep -rn --include='*.dart' -E "daily_log|Tables\.dailyLog" lib/domain/anchor/ 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*//')
if [ -n "$ANCHOR_WRITES_LOG" ]; then
  bad "anchor 层碰了 daily_log（写库唯一通道是 CaptureRepository.commit）："
  printf '%s\n' "$ANCHOR_WRITES_LOG"
else
  ok "anchor 层没有碰 daily_log"
fi

echo "== 5. 依赖清单 =="
note "flutter_riverpod ^2.5.1 / sqflite ^2.3.3 / flutter_local_notifications ^17.2.1"
note "share_plus ^9.0.0 / timezone ^0.9.2 / path_provider ^2.1.3 / fl_chart ^0.68.0"

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m预检通过。下一步：bash tools/build_apk.sh\033[0m\n'
else
  printf '\033[31m预检有问题，先修上面标 ✗ 的项。\033[0m\n'
fi
exit "$FAIL"
