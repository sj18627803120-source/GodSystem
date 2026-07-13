from __future__ import annotations

import re
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LUA_ROOT = ROOT / "Contents" / "mods" / "GodSystem" / "42" / "media" / "lua"
SOURCE = Path(__file__).with_name("godsystem_v11645_localization.yml")
CN_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "IG_UI_CN.txt"
CH_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "IG_UI_CH.txt"
CN_ITEMS_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Items_CN.txt"
CH_ITEMS_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Items_CH.txt"
CN_ITEM_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "ItemName.json"
CH_ITEM_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "ItemName.json"
CN_TOOLTIP_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Tooltip.json"
CH_TOOLTIP_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Tooltip.json"
OVERRIDE_PATH = LUA_ROOT / "shared" / "GodSystem_Localization_Override.lua"
ADMIN_CONFIG_PATH = LUA_ROOT / "shared" / "GodSystem_AdminConfig.lua"
SANDBOX_OPTIONS_PATH = LUA_ROOT.parent / "sandbox-options.txt"
CN_SANDBOX_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Sandbox.json"
CH_SANDBOX_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Sandbox.json"
REMOVED_UI_KEYS = {
    "Companion_VisualHuman",
    "Companion_VisualOrb",
    "Companion_SwitchHuman",
    "Companion_SwitchOrb",
    "Companion_CopyAppearance",
    "Notify_CompanionAppearanceCopied",
}


def parse_flat_yaml(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r'([A-Za-z0-9_.]+):\s*"(.*)"', line)
        if not match:
            raise ValueError(f"Unsupported YAML line {line_no}: {raw}")
        key, value = match.groups()
        entries[key] = value.replace(r"\"", '"').replace(r"\\", "\\")
    return entries


def lua_escape(text: str) -> str:
    return "".join(f"\\{byte}" for byte in text.encode("utf-8"))


def scalar_tail(expression: str) -> str:
    value = expression.strip()
    investment = re.fullmatch(r'investmentDefault\([^,]+,[^,]+,\s*(-?\d+(?:\.\d+)?)\)', value)
    if investment:
        return investment.group(1)
    if " or " in value:
        value = value.rsplit(" or ", 1)[1].strip()
    if not re.fullmatch(r"(?:true|false|-?\d+(?:\.\d+)?)", value):
        raise ValueError(f"Unsupported sandbox scalar: {expression}")
    return value


def parse_admin_meta() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    pattern = re.compile(r'^\s*\{\s*key\s*=\s*"([^"]+)"(.*?)\},\s*$')
    field_pattern = re.compile(r'([A-Za-z]+)\s*=\s*(investmentDefault\([^)]*\)|"[^"]*"|[^,}]+)')
    for raw in ADMIN_CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        match = pattern.match(raw)
        if not match:
            continue
        key, rest = match.groups()
        fields = {name: value.strip().strip('"') for name, value in field_pattern.findall(rest)}
        if not {"group", "type", "default", "labelKey", "descKey"}.issubset(fields):
            continue
        fields["key"] = key
        rows.append(fields)
    if len(rows) != 68:
        raise ValueError(f"Expected 68 admin settings, found {len(rows)}")
    return rows


def parse_translate(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    pattern = re.compile(r'^\s*IGUI_GodSystem_([A-Za-z0-9_]+)\s*=\s*"(.*)",\s*$')
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(raw)
        if match:
            entries[match.group(1)] = match.group(2).replace(r'\"', '"').replace(r'\\', '\\')
    return entries


def write_sandbox_files() -> None:
    rows = parse_admin_meta()
    page_names = {"base": "基础设置", "economy": "经济设置", "features": "功能开关"}
    lines = ["VERSION = 1,", ""]
    page_names = {"base": "基础设置", "economy": "经济设置", "features": "功能开关"}
    for row in rows:
        option_type = "double" if row["type"] == "number" else row["type"]
        lines.extend([f'option GodSystem.{row["key"]}', "{", f"    type = {option_type},"])
        if "min" in row:
            lines.append(f'    min = {scalar_tail(row["min"])},')
        if "max" in row:
            lines.append(f'    max = {scalar_tail(row["max"])},')
        lines.extend([
            f'    default = {scalar_tail(row["default"])},',
            f'    page = GodSystem_{row["group"].title()},',
            f'    translation = GodSystem_{row["key"]},',
            "}",
            "",
        ])
    SANDBOX_OPTIONS_PATH.write_text("\n".join(lines), encoding="utf-8", newline="\n")

    for translate_path, output_path in ((CN_PATH, CN_SANDBOX_PATH), (CH_PATH, CH_SANDBOX_PATH)):
        source = parse_translate(translate_path)
        output: dict[str, str] = {}
        for group, label in page_names.items():
            output[f"Sandbox_GodSystem_{group.title()}"] = label
        for row in rows:
            output[f'Sandbox_GodSystem_{row["key"]}'] = source.get(row["labelKey"], row["key"])
            output[f'Sandbox_GodSystem_{row["key"]}_tooltip'] = source.get(row["descKey"], row["key"])
        output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def translate_line(key: str, value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', r'\"')
    return f'    IGUI_GodSystem_{key} = "{escaped}",'


def update_translate(path: Path, entries: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    lines = [
        line for line in lines
        if not any(re.match(rf'\s*IGUI_GodSystem_{re.escape(key)}\s*=', line) for key in REMOVED_UI_KEYS)
    ]
    existing_keys = set()
    for idx, line in enumerate(lines):
        match = re.match(r'\s*IGUI_GodSystem_([A-Za-z0-9_]+)\s*=', line)
        if not match:
            continue
        key = match.group(1)
        if key in entries:
            lines[idx] = translate_line(key, entries[key])
            existing_keys.add(key)
    insert_at = len(lines)
    for idx, line in enumerate(lines):
        if line.strip() == "}":
            insert_at = idx
            break
    missing = [key for key in entries if key not in existing_keys]
    if missing:
        block = [translate_line(key, entries[key]) for key in missing]
        if insert_at > 0 and lines[insert_at - 1].strip():
            block.insert(0, "")
        lines[insert_at:insert_at] = block
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def item_line(key: str, value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', r'\"')
    return f'    {key} = "{escaped}",'


def update_item_translate(path: Path, entries: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    existing_keys = set()
    for idx, line in enumerate(lines):
        match = re.match(r'\s*([A-Za-z0-9_.]+)\s*=', line)
        if not match:
            continue
        key = match.group(1)
        if key in entries:
            lines[idx] = item_line(key, entries[key])
            existing_keys.add(key)
    insert_at = next((idx for idx, line in enumerate(lines) if line.strip() == "}"), len(lines))
    missing = [key for key in entries if key not in existing_keys]
    if missing:
        block = [item_line(key, entries[key]) for key in missing]
        if insert_at > 0 and lines[insert_at - 1].strip():
            block.insert(0, "")
        lines[insert_at:insert_at] = block
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_json(path: Path, entries: dict[str, str]) -> None:
    path.write_text(json.dumps(entries, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")


def fallback_line(key: str, value: str) -> str:
    return f'GodSystemFallbackText.zh["{key}"] = "{lua_escape(value)}"'


def update_override(path: Path, entries: dict[str, str]) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    lines = [
        line for line in lines
        if not any(re.match(rf'GodSystemFallbackText\.zh\["{re.escape(key)}"\]\s*=', line) for key in REMOVED_UI_KEYS)
    ]
    existing_keys = set()
    for idx, line in enumerate(lines):
        match = re.match(r'GodSystemFallbackText\.zh\["([A-Za-z0-9_]+)"\]\s*=', line)
        if not match:
            continue
        key = match.group(1)
        if key in entries:
            lines[idx] = fallback_line(key, entries[key])
            existing_keys.add(key)
    for key, value in entries.items():
        if key not in existing_keys:
            lines.append(fallback_line(key, value))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    entries = parse_flat_yaml(SOURCE)
    item_entries = {
        key: value for key, value in entries.items()
        if key.startswith("ItemName_") or key.startswith("Tooltip_GodSystem_")
    }
    ui_entries = {key: value for key, value in entries.items() if key not in item_entries}
    update_translate(CN_PATH, ui_entries)
    update_translate(CH_PATH, ui_entries)
    update_item_translate(CN_ITEMS_PATH, item_entries)
    update_item_translate(CH_ITEMS_PATH, item_entries)
    item_name_json = {
        key[len("ItemName_"):]: value
        for key, value in item_entries.items()
        if key.startswith("ItemName_")
    }
    tooltip_json = {
        key: value
        for key, value in item_entries.items()
        if key.startswith("Tooltip_GodSystem_")
    }
    write_json(CN_ITEM_JSON_PATH, item_name_json)
    write_json(CH_ITEM_JSON_PATH, item_name_json)
    write_json(CN_TOOLTIP_JSON_PATH, tooltip_json)
    write_json(CH_TOOLTIP_JSON_PATH, tooltip_json)
    update_override(OVERRIDE_PATH, ui_entries)
    write_sandbox_files()
    print(f"updated {len(ui_entries)} UI keys, {len(item_entries)} item keys, and 68 sandbox options")


if __name__ == "__main__":
    main()
