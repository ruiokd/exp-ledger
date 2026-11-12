#!/usr/bin/env python3
"""把本地 HEAD 推上 GitHub —— 走 api.github.com，不碰 github.com:443。

为什么需要它：沙箱里 `git push` 经常在 TLS 阶段就断
（`GnuTLS recv error (-110)` / `Failed to connect to github.com port 443`），
但 `api.github.com` 一直是通的。git 协议走 443 直连，REST API 走另一条路，
于是用 Git Data API 手工造一个 commit：blob → tree → commit → 更新 ref。

关键设计：**本地 commit 的元数据（message / author / committer / date / tree）
全从本地 HEAD 读出来，原样提交给 API**。这样 GitHub 算出来的 commit sha
和本地一致，推完之后本地与远端不产生"内容相同但 sha 不同"的分叉，
以后网络恢复还能正常 `git fetch / push`。

用法：
    python3 tools/api_push.py <token>            # 推当前分支
    python3 tools/api_push.py <token> --dry-run  # 只造对象，不动 ref

token 权限（classic）：repo（含 workflow）。
"""
import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

REPO = "ruiokd/exp-ledger"
BRANCH = "main"
API = "https://api.github.com"


def sh(*args: str) -> bytes:
    return subprocess.run(args, check=True, capture_output=True).stdout


def text(*args: str) -> str:
    return sh(*args).decode().strip()


class Gh:
    def __init__(self, token: str) -> None:
        self.token = token

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            API + path,
            data=data,
            method=method,
            headers={
                "Authorization": "Bearer " + self.token,
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json",
                "User-Agent": "exp-ledger-ship",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as err:
            detail = err.read().decode(errors="replace")[:600]
            raise SystemExit(f"✗ {method} {path} → {err.code}\n{detail}") from None


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("用法：python3 tools/api_push.py <token> [--dry-run]")
    token = sys.argv[1]
    dry = "--dry-run" in sys.argv
    gh = Gh(token)

    who = gh.call("GET", "/user").get("login")
    if not who:
        raise SystemExit("✗ token 无效")
    print(f"✓ 已认证：{who}")

    head = text("git", "rev-parse", "HEAD")
    parent = gh.call("GET", f"/repos/{REPO}/git/ref/heads/{BRANCH}")["object"]["sha"]
    local_parent = text("git", "rev-parse", "HEAD^")
    if local_parent != parent:
        raise SystemExit(
            f"✗ 本地 HEAD^ = {local_parent[:8]}，远端 main = {parent[:8]}："
            "历史不同源，先用 git fetch 对齐（或把本地 rebase 到远端）再推"
        )
    tree_parent = gh.call("GET", f"/repos/{REPO}/git/commits/{parent}")["tree"]["sha"]
    print(f"  远端 main {parent[:8]} / tree {tree_parent[:8]}")

    changed = [
        line.split("\t")
        for line in text("git", "diff", "--name-status", parent, head).splitlines()
        if line
    ]
    if not changed:
        print("✓ 没有变化，不需要推")
        return

    entries = []
    for status, path in changed:
        if status == "D":
            entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
            print(f"  D {path}")
            continue
        blob = sh("git", "cat-file", "-p", f"HEAD:{path}")
        created = gh.call(
            "POST",
            f"/repos/{REPO}/git/blobs",
            {"content": base64.b64encode(blob).decode(), "encoding": "base64"},
        )
        mode = text("git", "ls-tree", "HEAD", "--", path).split()[0]
        entries.append({"path": path, "mode": mode, "type": "blob", "sha": created["sha"]})
        print(f"  {status} {path}  ({len(blob)} B, mode {mode})")

    tree = gh.call(
        "POST", f"/repos/{REPO}/git/trees", {"base_tree": tree_parent, "tree": entries}
    )
    # 消息必须逐字节取自 commit 对象：`git log --format=%B` 会吃掉结尾换行，
    # 换行少一个 sha 就完全不同（第一次就这么踩了）。
    raw = sh("git", "cat-file", "commit", head)
    message = raw.partition(b"\n\n")[2].decode()
    meta = {
        "name": text("git", "log", "-1", "--format=%an"),
        "email": text("git", "log", "-1", "--format=%ae"),
        "date": text("git", "log", "-1", "--format=%aI"),
    }
    cmeta = {
        "name": text("git", "log", "-1", "--format=%cn"),
        "email": text("git", "log", "-1", "--format=%ce"),
        "date": text("git", "log", "-1", "--format=%cI"),
    }
    commit = gh.call(
        "POST",
        f"/repos/{REPO}/git/commits",
        {
            "message": message,
            "tree": tree["sha"],
            "parents": [parent],
            "author": meta,
            "committer": cmeta,
        },
    )
    print(f"  本地 tree {text('git', 'rev-parse', head + '^{tree}')[:8]}"
          f" / 远端 tree {tree['sha'][:8]}")
    print(f"  远端 commit {commit['sha'][:12]} / 本地 HEAD {head[:12]}")
    if commit["sha"] != head:
        print("  ! sha 不一致（元数据或 tree 有差异），下面这步会让本地分叉：")
        print("    推完用 git fetch && git reset --hard origin/main 对齐")
    else:
        print("  ✓ sha 与本地完全一致，推完不分叉")

    if dry:
        print("（--dry-run：没有更新 ref）")
        return
    gh.call(
        "PATCH",
        f"/repos/{REPO}/git/refs/heads/{BRANCH}",
        {"sha": commit["sha"], "force": False},
    )
    print(f"✓ 已更新 {BRANCH} → {commit['sha'][:12]}")


if __name__ == "__main__":
    main()
