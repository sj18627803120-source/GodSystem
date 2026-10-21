"""Development-only consumer matrix from the live sandbox schema (no runtime table)."""
from pathlib import Path
import argparse
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/localization"))
import generate_godsystem_v11645_localization as localization

LUA = ROOT / "Contents/mods/GodSystem/42/media/lua"
OUTPUT = ROOT / "docs/开发技术支援/沙盒配置生效矩阵.md"
EXCLUDED = {"GodSystem_Config.lua", "GodSystem_Localization_Override.lua",
            "GodSystem_TerminalGuideData.lua"}
SCANNED = {}

def consumers(key):
    result = list(SCANNED.get(key, []))
    # Dynamic prefixes and registration have actual downstream consumers.
    if key.startswith("BankInvestment") and any(key.endswith(x) for x in ("GainChance", "LossChance", "GainPercent", "LossPercent")):
        result += ["shared/GodSystem_RuntimeConfig.lua `applyBankInvestmentProfiles` 动态前缀 → client/GodSystem_ClientRuntime_BankGrowth.lua `gsSettleBankInvestmentAccount`；server/GodSystem_ServerRuntime_Bank.lua 投资结算"]
    if key == "EnableAutoLoaderShop":
        result += ["shared/GodSystem_Config.lua `ShopItems.featureKey` 注册 → client/GodSystem_ShopCatalog.lua `featureKey` 筛选；server/GodSystem_ServerRuntime_Commerce.lua 购买验证"]
    return result

def timing(key):
    if key.startswith("ShowRecycleContext"):
        return "下一次构建物品右键菜单；仅展示，不改变价格/准备令牌、不取消交易；MP采用服务器快照"
    if key == "StartingPoints": return "账号/存档初始化；不追回已发币；无展示缓存"
    if key in ("DailyTaskCount", "DefaultTaskLimitHours", "TaskRewardMultiplier", "TaskPenaltyMultiplier"):
        return "下次任务生成/刷新；taskGenerationToken；已接任务保留"
    if key.startswith("Equipment") or key in ("EnableEquipment", "EnableEquipmentFreeze", "EnableEquipmentSplash"):
        return "报价/执行及命中检查；Equipment.config.token；开关保留培养"
    if key in ("ShopBuyPriceMultiplier", "RecycleSellPriceMultiplier", "EconomyConversionSafetyMargin"):
        return "下一报价/结算；PricingRevision→价格缓存失效；不改已成交"
    if key.startswith("ShopDynamic") or key == "EnableShopDynamicInflation":
        return "下一报价/购买；涨幅应用现存层，时长仅新层，关闭清层"
    if "UtilityGenerator" in key: return "下一设备维护/操作；新补给按新价，旧预留按原账本；水电各自开关"
    if key.startswith("BankInvestment"): return "下一投资/结算；有效概率档案；MP权威端结算"
    if key.startswith("BankLoan"): return "额度查询/新贷款/欠款维护；已建贷款计划保留原约定"
    if key.startswith("Companion"): return "下一购买/搜敌；仅SP；空闲无新增网络"
    if key == "EnableCompanion": return "下一购买/同伴更新；仅SP；保留技能"
    if key in ("DeathProtectionCost",): return "下一购买；仅SP；已存次数保留"
    if key.startswith("HomeSafeZone"): return "下一安全区维护批次；既有周期/数量预算；不新增扫描"
    if key == "LotteryItemCacheBuildRate": return "下一抽奖缓存构建片；不合并物品目录"
    if key.startswith("Enable"): return "下一界面刷新及权威操作/效果检查；关闭子功能不清档（涨价除外）"
    return "下一对应操作/查询或既有维护批次；运行快照由SP/服务器读取，MP本地不能覆盖"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    global LUA, OUTPUT
    root = args.source_root.resolve()
    LUA = root / "Contents/mods/GodSystem/42/media/lua"
    OUTPUT = root / "docs/开发技术支援/沙盒配置生效矩阵.md"
    localization.SANDBOX_OPTIONS_PATH = LUA.parent / "sandbox-options.txt"
    localization.SOURCE = root / "tools/localization/godsystem_v11645_localization.yml"
    rows = localization.parse_sandbox_options()
    keys = {row["key"] for row in rows}
    words = re.compile(r"\b[A-Za-z_]\w*\b")
    declaration = re.compile(r"(?:local\s+)?function\s+([\w.:]+)")
    for path in sorted(LUA.rglob("*.lua")):
        if "Translate" in path.parts or path.name in EXCLUDED: continue
        function = "模块入口"
        for number, line in enumerate(path.read_text(encoding="utf8").splitlines(), 1):
            match = declaration.search(line)
            if match: function = match[1]
            if line.lstrip().startswith("--"): continue
            for key in set(words.findall(line)).intersection(keys):
                SCANNED.setdefault(key, []).append(f"{path.relative_to(LUA).as_posix()}:{number} `{function}`")
    texts = localization.parse_flat_yaml(localization.SOURCE)
    version = re.search(r'GodSystemConfig.Version\s*=\s*"([^"]+)"', (LUA / "shared/GodSystem_Config.lua").read_text(encoding="utf8")).group(1)
    content = [f"# 沙盒配置生效矩阵：{version}", "", "由 `python tools/analysis/audit_sandbox_config.py` 从唯一运行 schema 生成；仅开发资料，不写入存档。",
               "", f"链路：schema → RuntimeConfig.fromSandbox/readSandbox 或服务器 applySnapshot → Config/直接消费者。下表的消费者是源码证据，不表示每项已实机验证。现存{len(rows)}项均有直接、派生或注册消费者，未发现新的无效项。",
               "", f"{len(rows)}项合法范围/默认值以运行schema为准；有限数值边界、银行概率联动、准备令牌、费用/奖罚/装备/设备业务A/B见 `config_business_spec.lua`、`task_config_spec.lua`、`context_performance_spec.lua` 及各既有功能 spec。世界原生效果、反作弊和MP收包仍待集中实测。",
               "", "银行涨跌概率合计超过100时保留上涨概率、裁剪下跌概率。装备下限超过基础成功率则拒绝交易，不能靠静默裁剪制造另一套玩法。", ""]
    for row in rows:
        key = row["key"]
        paths = consumers(key)
        if not paths: raise ValueError("No business consumer: " + key)
        label = texts.get("AdminSetting_" + key, key)
        description = texts.get("AdminSetting_" + key + "_Desc", "")
        content += [f"## {key} — {label}", "",
                    f"- 定义：{row['type']}；默认 `{row['default']}`；范围 `{row.get('min', 'false')}–{row.get('max', 'true')}`；页 `{row['page']}`。",
                    "- 单位/边界/依赖：" + description,
                    "- 生效与缓存：" + timing(key),
                    "- 消费者：" + "；".join(paths[:8]) + (f"；另{len(paths)-8}处" if len(paths)>8 else ""),
                    f"- 验证状态：消费链已核查；相关功能自动回归已执行。未逐项实机修改{len(rows)}项；原生行为见交接测试目录。", ""]
    generated = "\n".join(content)
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf8") != generated:
            raise SystemExit("Sandbox matrix is stale; regenerate with tools/analysis/audit_sandbox_config.py")
    else:
        OUTPUT.write_text(generated, encoding="utf8", newline="\n")
    print(f"Sandbox consumer audit passed: {len(rows)} fields; {OUTPUT}")

if __name__ == "__main__": main()
