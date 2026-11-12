#!/usr/bin/env python3
"""跨文件符号检查：抓"用了项目里定义的类型但没 import"这类编译错误。

沙箱没有 Dart SDK，`flutter analyze` 跑不了。这个脚本退一步：
  · 先建全项目符号表（class / enum / typedef / mixin / extension / 顶层函数）；
  · 再对每个文件算"可见符号"= 本文件定义 + 直接 import 的文件定义；
  · 凡是引用了项目内符号却不可见的，报出来。

Dart 的 import 不传递，所以"间接 import 到"也算错的——
这正是 analyze 会报 undefined_identifier 的那类问题。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
TEST = ROOT / "test"

DEF_PATTERNS = [
    re.compile(r"^(?:abstract\s+|sealed\s+|final\s+|base\s+)*class\s+([A-Z]\w*)", re.M),
    re.compile(r"^enum\s+([A-Z]\w*)", re.M),
    re.compile(r"^typedef\s+([A-Z]\w*)", re.M),
    re.compile(r"^mixin\s+([A-Z]\w*)", re.M),
    re.compile(r"^extension\s+([A-Z]\w*)", re.M),
    re.compile(r"^(?:[A-Za-z_][\w<>, ?]*)\s+([a-z]\w*)\s*\(", re.M),  # 顶层函数
]

IMPORT_RE = re.compile(r"import\s+'([^']+)'")
EXPORT_RE = re.compile(r"export\s+'([^']+)'")


def strip_code(text: str) -> str:
    """去掉注释与字符串内容，避免把文案里的英文当符号。"""
    out = []
    i, n = 0, len(text)
    mode = None
    while i < n:
        c = text[i]
        if mode == "line":
            if c == "\n":
                mode = None
                out.append(c)
            i += 1
            continue
        if mode == "block":
            if text.startswith("*/", i):
                mode = None
                i += 2
            i += 1
            continue
        if mode in ("'", '"'):
            if c == "\\":
                i += 2
                continue
            if c == mode:
                mode = None
            i += 1
            continue
        if mode in ("'''", '"""'):
            if text.startswith(mode, i):
                mode = None
                i += 3
                continue
            i += 1
            continue
        if text.startswith("//", i):
            mode = "line"
            i += 2
            continue
        if text.startswith("/*", i):
            mode = "block"
            i += 2
            continue
        if text.startswith("'''", i):
            mode = "'''"
            i += 3
            continue
        if text.startswith('"""', i):
            mode = '"""'
            i += 3
            continue
        if c in "'\"":
            mode = c
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def definitions(path: pathlib.Path) -> set[str]:
    text = strip_code(path.read_text(encoding="utf-8"))
    names: set[str] = set()
    for pattern in DEF_PATTERNS:
        names.update(pattern.findall(text))
    return names


def resolve(path: pathlib.Path, raw: str) -> pathlib.Path | None:
    """把 import/export 的字符串换算成本地文件。dart: 与外部包返回 None。"""
    if raw.startswith("dart:"):
        return None
    if raw.startswith("package:exp_ledger/"):
        return LIB / raw[len("package:exp_ledger/"):]
    if raw.startswith("package:"):
        return None
    # 其余都是相对路径（含不带 ./ 的裸文件名）
    return (path.parent / raw).resolve()


def _collect(path: pathlib.Path, regex: re.Pattern[str], seen: set[pathlib.Path]) -> set[pathlib.Path]:
    out: set[pathlib.Path] = set()
    if path in seen or not path.exists():
        return out
    seen.add(path)
    text = path.read_text(encoding="utf-8")
    for raw in regex.findall(text):
        target = resolve(path, raw)
        if target is not None and target.exists():
            out.add(target)
    return out


def imports_of(path: pathlib.Path) -> set[pathlib.Path]:
    """直接 import 的文件 + 它们通过 export 链暴露出来的文件（递归）。"""
    direct = _collect(path, IMPORT_RE, set())
    visible: set[pathlib.Path] = set()
    queue = list(direct)
    seen: set[pathlib.Path] = set()
    while queue:
        current = queue.pop()
        if current in seen:
            continue
        seen.add(current)
        visible.add(current)
        queue.extend(_collect(current, EXPORT_RE, set()))
    return visible


def main() -> int:
    files = sorted(LIB.rglob("*.dart")) + sorted(TEST.rglob("*.dart"))
    defs: dict[pathlib.Path, set[str]] = {f: definitions(f) for f in files}
    owner: dict[str, set[pathlib.Path]] = {}
    for f, names in defs.items():
        for n in names:
            owner.setdefault(n, set()).add(f)

    problems: list[str] = []
    for f in files:
        code = strip_code(f.read_text(encoding="utf-8"))
        visible: set[str] = set(defs[f])
        for dep in imports_of(f):
            visible |= defs.get(dep, set())
        referenced = set(re.findall(r"\b([A-Z]\w*)\b", code))
        for name in sorted(referenced):
            if name not in owner or name in visible:
                continue
            where = ", ".join(sorted(str(p.relative_to(ROOT)) for p in owner[name]))
            problems.append(
                f"{f.relative_to(ROOT)}: 引用了 {name}（定义于 {where}）但没有可见的 import"
            )

    if problems:
        print("\n".join(problems))
        print(f"\n共 {len(problems)} 处。")
        return 1

    print(f"检查 {len(files)} 个文件，{len(owner)} 个符号：没有缺失 import。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
