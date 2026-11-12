#!/usr/bin/env python3
"""从 resources/rules.json 生成 Swift 规则包，避免手写与清单不同步。"""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "resources" / "rules.json"
dst = root / "Sources" / "cleanmac" / "RulePack.swift"

data = json.loads(src.read_text(encoding="utf-8"))

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')

lines = [
    "// 由 tools/gen_rules.py 从 resources/rules.json 生成，请勿手改",
    "import Foundation",
    "",
    "enum RulePack {",
    "    /// 清单来源：docs/清理清单.md",
    "",
    "    static let all: [Rule] = [",
]

for r in data["rules"]:
    t = r["target"]
    path = esc(r["path"])
    if t == "files":
        exts = ", ".join(f'"{e}"' for e in r.get("exts", []))
        target = f'.files("{path}", [{exts}])'
    else:
        target = f'.{t}("{path}")'
    lines.append(
        f'        Rule(id: "{r["id"]}", category: .{r["category"]}, '
        f'title: "{esc(r["title"])}", detail: "{esc(r["detail"])}", '
        f'target: {target}, risk: .{r["risk"]}),'
    )

lines += ["    ]", "}", ""]
dst.write_text("\n".join(lines), encoding="utf-8")
print(f"生成 {dst.name}：{len(data['rules'])} 条规则")
