#!/usr/bin/env bash
# 一条命令出安装包：推送 → 等 CI → 把 APK 拉回本地。
#
# 为什么要有这个脚本：沙箱是 aarch64，aapt2 / zipalign 只有 x86_64 版本，
# 本地跑不了 `flutter build apk`（会 Exec format error）。所以 APK 只能在
# GitHub Actions 的 x64 runner 上出。这个脚本把「推代码 + 等构建 + 下载 + 落盘」
# 串成一步，省掉来回开网页。
#
# 用法：
#   bash tools/ship.sh ghp_xxxxxxxx            # 参数给 token
#   GITHUB_TOKEN=ghp_xxx bash tools/ship.sh    # 或走环境变量
#
# 需要的 token 权限（classic）：repo（含 workflow）+ actions:read
# 细粒度 token：Contents=Read and write、Actions=Read、Workflows=Read and write
#
# 产物落点：dist/exp-ledger-<版本>.apk 与 /chat/outputs/exp-ledger-<版本>.apk
set -uo pipefail
cd "$(dirname "$0")/.."

REPO="ruiokd/exp-ledger"
BRANCH="main"
API="https://api.github.com"
TOKEN="${1:-${GITHUB_TOKEN:-}}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
say() { printf '  %s\n' "$*"; }
die() { red "✗ $*"; exit 1; }

[ -n "$TOKEN" ] || die "没给 token。用法：bash tools/ship.sh ghp_xxx（classic token 勾 repo）"
command -v python3 >/dev/null || die "缺 python3（解析 JSON 用）"

api() { # api <path> [curl 额外参数...]
  local path="$1"; shift
  curl -sS -H "Authorization: Bearer $TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" "$@" "$API$path"
}
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }

echo "== 1. 校验 token =="
WHO=$(api /user | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('login',''))")
[ -n "$WHO" ] || die "token 无效或没网"
grn "✓ 已认证：$WHO"

echo "== 2. 推送 $BRANCH =="
SHA=$(git rev-parse HEAD)
say "本地 HEAD ${SHA:0:8}（$(git log -1 --format=%s | cut -c1-44)…）"
# 优先走 git 协议：用 x-access-token 形式，权限只活在这条命令里，不写进 .git/config
if timeout 45 git push --quiet "https://x-access-token:$TOKEN@github.com/$REPO.git" "$BRANCH" 2>/tmp/pushi.err; then
  grn "✓ 已推送（git）"
else
  say "git push 没成：$(tail -1 /tmp/pushi.err | cut -c1-90)"
  say "改用 api.github.com（github.com:443 在沙箱里经常被断，API 那条路一直通）"
  python3 tools/api_push.py "$TOKEN" || die "两条路都没推上去，检查 token 的 Contents=write"
  grn "✓ 已推送（API）"
fi

echo "== 3. 等 CI（build-apk）=="
RUN_ID=""
for i in $(seq 1 24); do
  sleep 5
  # 前 30 秒只认 head_sha 完全一致（避免抓到上一次的旧 run）；
  # 之后退而取该分支最新的 run —— API 推送出来的 sha 可能和本地不同。
  [ "$i" -ge 6 ] && export FALLBACK=1
  RUN_ID=$(api "/repos/$REPO/actions/runs?branch=$BRANCH&per_page=10" \
    | SHA="$SHA" python3 -c "
import sys,json,os
sha=os.environ['SHA']
runs=json.load(sys.stdin).get('workflow_runs',[])
hit=[r for r in runs if r.get('head_sha')==sha]
if hit:
    print(hit[0]['id'])
elif os.environ.get('FALLBACK')=='1' and runs:
    print(max(runs,key=lambda r:r['id'])['id'])
" 2>/dev/null)
  [ -n "$RUN_ID" ] && break
done
[ -n "$RUN_ID" ] || die "两分钟没看到 workflow run，去网页看一眼：https://github.com/$REPO/actions"
say "run $RUN_ID"
grn "✓ 已触发"

STATUS=""; CONCLUSION=""
for i in $(seq 1 300); do # 300 × 10s ≈ 50 分钟上限
  sleep 10
  read -r STATUS CONCLUSION <<<"$(api "/repos/$REPO/actions/runs/$RUN_ID" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('status',''),d.get('conclusion') or '-')")"
  printf '  [%3ds] %s / %s\n' "$((i*10))" "$STATUS" "$CONCLUSION"
  [ "$STATUS" = "completed" ] && break
done

if [ "$CONCLUSION" != "success" ]; then
  red "✗ 构建没通过（$CONCLUSION）。失败的步骤："
  api "/repos/$REPO/actions/runs/$RUN_ID/jobs" | python3 -c "
import sys,json
for j in json.load(sys.stdin).get('jobs',[]):
    for s in j.get('steps',[]):
        if s.get('conclusion') not in (None,'success','skipped'):
            print('   ✗', j['name'], '/', s['name'], s.get('conclusion'))
"
  echo "  日志：https://github.com/$REPO/actions/runs/$RUN_ID"
  exit 1
fi

echo "== 4. 下载 artifact =="
ART_URL=$(api "/repos/$REPO/actions/runs/$RUN_ID/artifacts" | python3 -c "
import sys,json
arts=[a for a in json.load(sys.stdin).get('artifacts',[]) if a.get('name','').startswith('exp-ledger-apk')]
arts.sort(key=lambda a:a['name'])
print(arts[0]['archive_download_url'] if arts else '')
")
[ -n "$ART_URL" ] || die "这个 run 没有 artifact（可能被 30 天清理，或上传步骤失败的早）"

TMP=$(mktemp -d)
curl -sSL -H "Authorization: Bearer $TOKEN" -o "$TMP/apk.zip" "$ART_URL" || die "下载失败"
unzip -q -o "$TMP/apk.zip" -d "$TMP/out" || die "解压失败（artifact 不是 zip？）"
SRC=$(find "$TMP/out" -name '*.apk' | head -1)
[ -n "$SRC" ] || die "artifact 里没有 .apk"

VER=$(grep -o 'versionName = "[^"]*"' android/app/build.gradle.kts | cut -d'"' -f2)
mkdir -p dist /chat/outputs 2>/dev/null || true
DEST="dist/exp-ledger-$VER.apk"
cp "$SRC" "$DEST"
cp "$SRC" "/chat/outputs/exp-ledger-$VER.apk" 2>/dev/null || true
rm -rf "$TMP"

echo
grn "✓ 出包完成：$DEST"
say "大小 $(du -h "$DEST" | cut -f1) / sha256 $(sha256sum "$DEST" | cut -c1-16)…"
echo
echo "装机：覆盖安装即可（签名已固定，不用卸载）。装完先看能不能进首页。"
