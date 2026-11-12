#!/usr/bin/env bash
# 一键构建 APK：预检 → 取依赖 → 分析 → 数据层测试 → 打包。
#
# 用法：
#   bash tools/build_apk.sh            # release（debug 签名，可直接装机）
#   bash tools/build_apk.sh --debug    # debug 包，装得快
#   bash tools/build_apk.sh --skip-tests
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="release"
RUN_TESTS=1
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="debug" ;;
    --skip-tests) RUN_TESTS=0 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done

echo "== 预检 =="
bash tools/preflight.sh

echo "== 取依赖 =="
flutter pub get

echo "== 静态分析 =="
# info 不阻断（比如 prefer_const_constructors 这种风格建议），error/warning 必须为 0。
if ! flutter analyze --no-fatal-infos; then
  echo "analyze 有 error 或 warning，先修。"
  exit 1
fi

if [ "$RUN_TESTS" -eq 1 ]; then
  echo "== 数据层测试 =="
  flutter test test/data/ --reporter compact
fi

echo "== 打包（$MODE）=="
if [ "$MODE" = "debug" ]; then
  flutter build apk --debug
else
  flutter build apk --release --target-platform android-arm64,android-arm
fi

APK_DIR="build/app/outputs/flutter-apk"
echo
echo "== 产物 =="
ls -lh "$APK_DIR"/*.apk 2>/dev/null || { echo "没找到 APK，检查上面的报错"; exit 1; }
echo
echo "装到设备：adb install -r $APK_DIR/app-$MODE.apk"
echo "看日志：  adb logcat -s flutter"
