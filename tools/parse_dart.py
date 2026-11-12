#!/usr/bin/env python3
"""用 tree-sitter 的 Dart 语法树逐文件解析，抓真正的语法错误。

为什么需要它：沙箱没有 Dart SDK，`flutter analyze` 跑不了；
但"能不能 parse"和"能不能编译"高度相关——括号错位、record 语法用错、
switch 表达式写坏，都会在这里现形。

比手写括号计数强的地方：它认得字符串插值、raw string、三引号、
泛型嵌套、模式匹配，不会把 `'${a['b']}'` 里的表情当成括号。

依赖（一次性）：
    pip install --break-system-packages tree_sitter tree_sitter_dart
"""
from __future__ import annotations

import pathlib
import sys

try:
    from tree_sitter import Language, Parser
    import tree_sitter_dart as tsd
except ImportError:
    print("缺依赖：pip install --break-system-packages tree_sitter tree_sitter_dart")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent


def collect_errors(node, source: bytes, out: list[str], limit: int = 6) -> None:
    if len(out) >= limit:
        return
    if node.type == "ERROR" or node.is_missing:
        start = node.start_point
        end = node.end_point
        snippet = source[node.start_byte : min(node.end_byte, node.start_byte + 120)]
        text = snippet.decode("utf-8", "replace").replace("\n", "\\n")
        kind = "MISSING" if node.is_missing else "ERROR"
        out.append(
            f"  {start[0] + 1}:{start[1] + 1}-{end[0] + 1}:{end[1] + 1} [{kind}] {text}"
        )
        return
    for child in node.children:
        collect_errors(child, source, out, limit)


def main() -> int:
    parser = Parser(Language(tsd.language()))
    files = sorted(ROOT.glob("lib/**/*.dart")) + sorted(ROOT.glob("test/**/*.dart"))
    broken: list[tuple[pathlib.Path, list[str]]] = []

    for path in files:
        source = path.read_bytes()
        tree = parser.parse(source)
        if not tree.root_node.has_error:
            continue
        errors: list[str] = []
        collect_errors(tree.root_node, source, errors)
        broken.append((path, errors))

    if not broken:
        print(f"解析 {len(files)} 个 Dart 文件：全部通过（0 个语法错误）。")
        return 0

    for path, errors in broken:
        print(f"\n{path.relative_to(ROOT)}")
        print("\n".join(errors))
    print(f"\n{len(broken)} 个文件有语法错误。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
