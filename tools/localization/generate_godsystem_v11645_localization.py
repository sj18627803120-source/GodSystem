from __future__ import annotations

import re
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LUA_ROOT = ROOT / "Contents" / "mods" / "GodSystem" / "42" / "media" / "lua"
SOURCE = Path(__file__).with_name("godsystem_v11645_localization.yml")
EN_CARRY_SOURCE = Path(__file__).with_name("godsystem_carry_en.yml")
EN_MIMIC_SOURCE = Path(__file__).with_name("godsystem_mimic_en.yml")
EN_SPLASH_SOURCE = Path(__file__).with_name("godsystem_splash_en.yml")
EN_UTILITY_GENERATOR_SOURCE = Path(__file__).with_name("godsystem_utilitygenerator_en.yml")
EN_PATH = LUA_ROOT / "shared" / "Translate" / "EN" / "IG_UI_EN.txt"
CN_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "IG_UI_CN.txt"
CH_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "IG_UI_CH.txt"
CN_ITEMS_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Items_CN.txt"
CH_ITEMS_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Items_CH.txt"
CN_ITEM_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "ItemName.json"
CH_ITEM_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "ItemName.json"
CN_TOOLTIP_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Tooltip.json"
CH_TOOLTIP_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Tooltip.json"
EN_ITEMS_PATH = LUA_ROOT / "shared" / "Translate" / "EN" / "Items_EN.txt"
EN_ITEM_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "EN" / "ItemName.json"
EN_TOOLTIP_JSON_PATH = LUA_ROOT / "shared" / "Translate" / "EN" / "Tooltip.json"
OVERRIDE_PATH = LUA_ROOT / "shared" / "GodSystem_Localization_Override.lua"
ITEM_FALLBACK_PATH = LUA_ROOT / "shared" / "GodSystem_Localization.lua"
ITEM_SCRIPT_PATH = LUA_ROOT.parent / "scripts" / "GodSystem_Items.txt"
SANDBOX_OPTIONS_PATH = LUA_ROOT.parent / "sandbox-options.txt"
CN_SANDBOX_PATH = LUA_ROOT / "shared" / "Translate" / "CN" / "Sandbox.json"
CH_SANDBOX_PATH = LUA_ROOT / "shared" / "Translate" / "CH" / "Sandbox.json"
EN_SANDBOX_PATH = LUA_ROOT / "shared" / "Translate" / "EN" / "Sandbox.json"
REMOVED_UI_KEYS = {
    # 3.15 removed the restore-default action; built-in relations are now
    # disabled or deleted, and switching presets brings them back.
    "ConversionRisk_Restore",
    "ConversionRisk_Restored",
    "NotifyMP_ConversionRelationRestored",
    # 3.14 replaced the raw full-type editor with the model-driven picker UI;
    # the single Disable/Delete button became dynamic Disable/Delete titles.
    "ConversionRisk_DisableDelete",
    "Companion_VisualHuman",
    "Companion_VisualOrb",
    "Companion_SwitchHuman",
    "Companion_SwitchOrb",
    "Companion_CopyAppearance",
    "Notify_CompanionAppearanceCopied",
    "Upgrade_TerminalCompression",
    "Btn_UpgradeTerminalCompression",
    "Waist_Compression",
    "Waist_CompressionLimit",
    "Waist_Example",
    "Waist_CompressionResult",
    "Terminal_CompressionSkipped",
    "Terminal_Compressing",
    "Attribute_BuyToLevel",
    "Attribute_TargetLevelPrompt",
    "Waist_CapacityExtended",
    "Storage_Error_CoreHostNotEmpty",
    "Storage_Error_CapacityLockFailed",
    # 3.4 now uses generic increase/decrease Tooltip templates for every
    # registered persistent attribute; retain the dedicated freeze template.
    "Equipment_TooltipDamage",
    # 3.6 removed the raw weapon-stat enhancement presentation.  Keep stale
    # generated tables from reviving it when localization is regenerated.
    "Equipment_AttributeRow",
    "Equipment_Attr_damage",
    "Equipment_Attr_wear",
    "Equipment_Attr_speed",
    "Equipment_Attr_accuracy",
    "Equipment_Attr_recoil",
    "Equipment_BaseNote",
    "Equipment_GrowthRule",
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


def parse_sandbox_options() -> list[dict[str, str]]:
    """Read the B42 sandbox schema instead of the retired AdminConfig module."""
    rows: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    option_pattern = re.compile(r'^\s*option\s+GodSystem\.([A-Za-z0-9_]+)\s*$')
    field_pattern = re.compile(r'^\s*(type|min|max|default|page|translation|title)\s*=\s*([^,]+),\s*$')

    for line_no, raw in enumerate(SANDBOX_OPTIONS_PATH.read_text(encoding="utf-8").splitlines(), 1):
        option = option_pattern.match(raw)
        if option:
            if current is not None:
                raise ValueError(f"Sandbox option {current['key']} was not closed before line {line_no}")
            current = {"key": option.group(1)}
            continue
        if current is None:
            continue
        if raw.strip() == "}":
            required = {"type", "default", "page", "translation"}
            missing = required.difference(current)
            if missing:
                raise ValueError(f"Sandbox option {current['key']} is missing {', '.join(sorted(missing))}")
            expected_translation = f"GodSystem_{current['key']}"
            if current["translation"] != expected_translation:
                raise ValueError(
                    f"Sandbox option {current['key']} must use translation {expected_translation}, "
                    f"found {current['translation']}"
                )
            rows.append(current)
            current = None
            continue
        field = field_pattern.match(raw)
        if field:
            current[field.group(1)] = field.group(2).strip().strip('"')

    if current is not None:
        raise ValueError(f"Sandbox option {current['key']} was not closed")
    if not rows:
        raise ValueError("No GodSystem sandbox options found")
    keys = [row["key"] for row in rows]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate GodSystem sandbox option key")
    return rows


def parse_translate(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    pattern = re.compile(r'^\s*IGUI_GodSystem_([A-Za-z0-9_]+)\s*=\s*"(.*)",\s*$')
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(raw)
        if match:
            entries[match.group(1)] = match.group(2).replace(r'\"', '"').replace(r'\\', '\\')
    return entries


def write_sandbox_files(entries: dict[str, str], english_entries: dict[str, str]) -> int:
    """Generate sandbox translations from the live schema and YAML source text.

    The sandbox schema is now maintained directly in sandbox-options.txt.  This
    deliberately never rewrites it: regenerating translations must not restore
    the deleted AdminConfig model or alter a server's option defaults.
    """
    rows = parse_sandbox_options()
    performance_keys = {
        "EnableRangeRecycle", "RangeRecycleRadius", "RangeRecycleBatchIntervalSeconds",
        "LotteryItemCacheBuildRate", "HomeSafeZoneScanIntervalHours", "HomeSafeZoneScanBudget",
        "HomeSafeZoneClearLimit", "CompanionAttackSearchSeconds",
        "CompanionAttackSearchCandidateLimit", "MPBackgroundSyncMinutes",
    }
    for row in rows:
        key = row["key"]
        required = (f"AdminSetting_{key}", f"AdminSetting_{key}_Desc")
        missing = [entry for entry in required if entry not in entries]
        if missing:
            raise ValueError(f"Sandbox option {key} is missing YAML entries: {', '.join(missing)}")
        if "title" in row and f"SandboxTitle_{row['title']}" not in entries:
            raise ValueError(f"Sandbox title {row['title']} is missing YAML text")

    for output_path in (CN_SANDBOX_PATH, CH_SANDBOX_PATH):
        existing = json.loads(output_path.read_text(encoding="utf-8"))
        pages = sorted({row["page"] for row in rows})
        output: dict[str, str] = {
            f"Sandbox_{page}": existing.get(f"Sandbox_{page}", page)
            for page in pages
        }
        for row in rows:
            key = row["key"]
            label = entries[f"AdminSetting_{key}"]
            output[f"Sandbox_GodSystem_{key}"] = ("[性能] " if key in performance_keys else "") + label
            output[f"Sandbox_GodSystem_{key}_tooltip"] = entries[f"AdminSetting_{key}_Desc"]
            if "title" in row:
                title = row["title"]
                output[f"Sandbox_Title_{title}"] = entries[f"SandboxTitle_{title}"]
        output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    existing = json.loads(EN_SANDBOX_PATH.read_text(encoding="utf-8"))
    pages = sorted({row["page"] for row in rows})
    output = {f"Sandbox_{page}": existing.get(f"Sandbox_{page}", page) for page in pages}
    for row in rows:
        key = row["key"]
        label = english_entries.get(f"AdminSetting_{key}", existing.get(f"Sandbox_GodSystem_{key}", key))
        output[f"Sandbox_GodSystem_{key}"] = ("[Performance] " if key in performance_keys else "") + label
        output[f"Sandbox_GodSystem_{key}_tooltip"] = english_entries.get(
            f"AdminSetting_{key}_Desc", existing.get(f"Sandbox_GodSystem_{key}_tooltip", ""))
        if "title" in row:
            title = row["title"]
            output[f"Sandbox_Title_{title}"] = english_entries.get(f"SandboxTitle_{title}", title)
    EN_SANDBOX_PATH.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return len(rows)


def translate_line(key: str, value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', r'\"')
    return f'    IGUI_GodSystem_{key} = "{escaped}",'


def update_translate(path: Path, entries: dict[str, str], remove_obsolete: bool = True) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    lines = [
        line for line in lines
        if not remove_obsolete or not any(re.match(rf'\s*IGUI_GodSystem_{re.escape(key)}\s*=', line) for key in REMOVED_UI_KEYS)
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


def item_fallback_line(key: str, value: str) -> str:
    return f'GodSystemFallbackItems["{key}"] = "{lua_escape(value)}"'


def parse_item_script_requirements() -> tuple[set[str], set[str]]:
    text = ITEM_SCRIPT_PATH.read_text(encoding="utf-8")
    item_names = {
        f"GodSystem.{match.group(1)}"
        for match in re.finditer(r"(?m)^\s*item\s+([A-Za-z0-9_]+)\s*$", text)
    }
    tooltips = {
        match.group(1)
        for match in re.finditer(r"(?m)^\s*Tooltip\s*=\s*(Tooltip_GodSystem_[A-Za-z0-9_]+),\s*$", text)
    }
    if not item_names:
        raise ValueError("No GodSystem item definitions found")
    return item_names, tooltips


def validate_item_entries(entries: dict[str, str]) -> None:
    item_names, tooltips = parse_item_script_requirements()
    translated_names = {
        key[len("ItemName_"):]
        for key in entries
        if key.startswith("ItemName_")
    }
    translated_tooltips = {
        key for key in entries if key.startswith("Tooltip_GodSystem_")
    }
    missing_names = sorted(item_names.difference(translated_names))
    missing_tooltips = sorted(tooltips.difference(translated_tooltips))
    if missing_names or missing_tooltips:
        details = []
        if missing_names:
            details.append("item names: " + ", ".join(missing_names))
        if missing_tooltips:
            details.append("tooltips: " + ", ".join(missing_tooltips))
        raise ValueError("Missing GodSystem item localization: " + "; ".join(details))


def update_item_fallback(path: Path, entries: dict[str, str]) -> None:
    values = {
        key[len("ItemName_"):]: value
        for key, value in entries.items()
        if key.startswith("ItemName_")
    }
    lines = path.read_text(encoding="utf-8").splitlines()
    existing: set[str] = set()
    last_index = -1
    for index, line in enumerate(lines):
        match = re.match(r'GodSystemFallbackItems\["([A-Za-z0-9_.]+)"\]\s*=', line)
        if not match:
            continue
        last_index = index
        key = match.group(1)
        if key in values:
            lines[index] = item_fallback_line(key, values[key])
            existing.add(key)
    missing = [key for key in values if key not in existing]
    if missing:
        if last_index < 0:
            raise ValueError("GodSystemFallbackItems block is missing")
        lines[last_index + 1:last_index + 1] = [item_fallback_line(key, values[key]) for key in missing]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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
    validate_item_entries(item_entries)
    update_translate(CN_PATH, ui_entries)
    update_translate(CH_PATH, ui_entries)
    # Carry English text is source-controlled alongside the Chinese YAML.
    # Preserve unrelated legacy English entries until their own migration.
    update_translate(EN_PATH, parse_flat_yaml(EN_CARRY_SOURCE), remove_obsolete=False)
    en_mimic_entries = parse_flat_yaml(EN_MIMIC_SOURCE)
    update_translate(EN_PATH, {key: value for key, value in en_mimic_entries.items() if not key.startswith(("ItemName_", "Tooltip_GodSystem_"))}, remove_obsolete=False)
    update_translate(EN_PATH, parse_flat_yaml(EN_SPLASH_SOURCE), remove_obsolete=False)
    en_utility_entries = parse_flat_yaml(EN_UTILITY_GENERATOR_SOURCE)
    update_translate(EN_PATH, {key: value for key, value in en_utility_entries.items() if not key.startswith(("ItemName_", "Tooltip_GodSystem_"))}, remove_obsolete=False)
    write_json(EN_PATH.with_name("IG_UI.json"), {
        "IGUI_GodSystem_" + key: value for key, value in parse_translate(EN_PATH).items()
    })
    # B42 uses JSON translation categories. Retain the legacy tables and
    # generate the matching complete IGUI dictionaries from those same keys.
    for path in (CN_PATH, CH_PATH):
        write_json(path.with_name("IG_UI.json"), {
            "IGUI_GodSystem_" + key: value for key, value in parse_translate(path).items()
        })
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
    en_item_entries = {key: value for key, value in en_mimic_entries.items() if key.startswith(("ItemName_", "Tooltip_GodSystem_"))}
    en_item_entries.update({key: value for key, value in en_utility_entries.items() if key.startswith(("ItemName_", "Tooltip_GodSystem_"))})
    update_item_translate(EN_ITEMS_PATH, en_item_entries)
    write_json(EN_ITEM_JSON_PATH, {key[len("ItemName_"):]: value for key, value in en_item_entries.items() if key.startswith("ItemName_")})
    write_json(EN_TOOLTIP_JSON_PATH, {key: value for key, value in en_item_entries.items() if key.startswith("Tooltip_GodSystem_")})
    update_item_fallback(ITEM_FALLBACK_PATH, item_entries)
    update_override(OVERRIDE_PATH, ui_entries)
    english_sandbox_entries = {}
    for source in (EN_CARRY_SOURCE, EN_MIMIC_SOURCE, EN_SPLASH_SOURCE, EN_UTILITY_GENERATOR_SOURCE):
        english_sandbox_entries.update(parse_flat_yaml(source))
    sandbox_count = write_sandbox_files(entries, english_sandbox_entries)
    print(f"updated {len(ui_entries)} UI keys, {len(item_entries)} item keys, and {sandbox_count} sandbox options")


if __name__ == "__main__":
    main()
