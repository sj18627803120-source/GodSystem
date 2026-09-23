"""Offline B42 recipe/item audit for GodSystem conversion-price relations.

This tool is intentionally never loaded by the mod.  It records only simple
single-source fixed-output candidates; administrators add workshop relations
through the server-authoritative configuration UI.
"""
from __future__ import annotations
import hashlib, re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"D:\SteamLibrary\steamapps\common\ProjectZomboid\media\scripts\generated")
OUT = ROOT / "docs" / "GodSystem_DevHandoff_CN" / "104_v42.20_3.13_原版转换关系审查报告.md"

def digest(paths):
    h = hashlib.sha256()
    for p in sorted(paths): h.update(p.relative_to(GAME).as_posix().encode()); h.update(p.read_bytes())
    return h.hexdigest()[:16]

def main():
    recipes, items = list((GAME / "recipes").rglob("*.txt")), list((GAME / "items").rglob("*.txt"))
    if not recipes or not items: raise SystemExit(f"missing B42 generated scripts below {GAME}")
    simple = rejected = 0; examples = []
    def blocks(text):
        for match in re.finditer(r"\bcraftRecipe\s+([^\s{]+)\s*\{", text, re.I):
            depth, pos = 1, match.end()
            while pos < len(text) and depth:
                depth += (text[pos] == "{") - (text[pos] == "}"); pos += 1
            if depth == 0: yield match.group(1), text[match.end():pos-1]
    for path in recipes:
        text = path.read_text(encoding="utf-8", errors="replace")
        for name, body in blocks(text):
            if any(token in body.lower() for token in ("random", "lua", "tag[", "tags[", "fluid", "keep ", "mapper")):
                rejected += 1; continue
            inputs = re.search(r"\binputs\s*\{(.*?)\n\s*\}", body, re.S | re.I)
            output = re.search(r"\boutputs\s*\{(.*?)\n\s*\}", body, re.S | re.I)
            sources = re.findall(r"\bitem\s+(\d+)\s+\[?([\w.]+)\]?", inputs.group(1) if inputs else "", re.I)
            result = re.findall(r"\bitem\s+(\d+)\s+([\w.]+)", output.group(1) if output else "", re.I)
            if len(sources) == 1 and len(result) == 1 and sources[0][1] != result[0][1]:
                simple += 1
                if len(examples) < 16: examples.append((name, (sources[0][1], sources[0][0]), (result[0][1], result[0][0])))
            else: rejected += 1
    lines = [
        "# v42.20_3.13 原版转换关系审查报告",
        "", "- 游戏目标：Project Zomboid B42.20.4", f"- 审查日期：{date.today().isoformat()}",
        f"- 输入摘要：`{digest(recipes + items)}`", f"- 配方文件：{len(recipes)}；物品文件：{len(items)}",
        f"- 自动接受并发布：32；固定单来源初筛候选：{simple}；拒绝或人工复核：{rejected}",
        "- 运行期不会读取此扫描结果，也不会枚举配方。发布关系只来自 `GodSystem_ConversionRelations.lua`。",
        "", "## 规则", "", "候选必须是单一来源、固定数量输出，并且不包含随机、Lua 回调、标签、流体或保留材料。多材料、动态输出和无法证明的结果仅保留在审查范围，不会自动进入价格关系。",
        "", "## 初筛样例", "",
        "| 配方 | 来源 | 结果 |", "|---|---|---|",
    ]
    lines += [f"| `{n}` | `{s[0]} × {s[1]}` | `{r[0]} × {r[1] or 1}` |" for n,s,r in examples]
    lines += ["", "## 已发布基础关系", "", "垃圾袋盒按 `UseDelta=0.05` 固定折算为 20 个垃圾袋；其余启用关系见静态表。关系图在服务器保存前检查直接和间接循环，超过安全整数范围时拒绝用于报价。"]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(OUT)
if __name__ == "__main__": main()
