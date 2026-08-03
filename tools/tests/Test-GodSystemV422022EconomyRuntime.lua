local root = assert(arg[1], "42.20.2.2 repository root is required")
local luaRoot = root .. "/Contents/mods/GodSystem/42/media/lua"

package.path = luaRoot .. "/shared/?.lua;" .. package.path
local currentManager = nil
getScriptManager = function() return currentManager end

dofile(luaRoot .. "/shared/GodSystem_Config.lua")
dofile(luaRoot .. "/shared/GodSystem_Prices.lua")
dofile(luaRoot .. "/shared/GodSystem_AdminConfig.lua")

GodSystem = GodSystem or {}
GodSystem.isEconomicItemAllowed = function(fullType) return fullType ~= "Base.Hidden" end

dofile(luaRoot .. "/shared/GodSystem_EconomyPolicy.lua")
local Policy = assert(GodSystemEconomyPolicy, "economy policy did not load")
GodSystem.isEconomicItemAllowed = function(fullType) return fullType ~= "Base.Hidden" end

Policy.rebuildTransformIndex(nil)
local money = Policy.quote("Base.Money")
local bundle = Policy.quote("Base.MoneyBundle")
assert(money.recycleValue == 1, "one banknote must recycle for one coin")
assert(bundle.referenceBuy == 15, "MoneyBundle legacy reference price must remain visible")
assert(bundle.conversionValue == 100, "MoneyBundle must resolve to 100 terminal banknotes")
assert(bundle.safeMinimum == 110 and bundle.finalBuy == 110, "MoneyBundle safe shop price must be 110")
assert(bundle.verificationStatus == "verified", "MoneyBundle must be a verified deterministic conversion")

local unknown = Policy.quote("ThirdParty.ExperimentalCrate")
assert(unknown.recycleValue == 1, "unknown third-party recycle fallback must really be one")
assert(unknown.referenceBuy == 120 and unknown.finalBuy == 120 and unknown.safeMinimum == 0,
    "ordinary unknown third-party items must use the detected category price instead of the 550 risk floor")
assert(unknown.verificationStatus == "not_applicable" and unknown.unknownThirdParty == true,
    "an unknown third-party item without a conversion must not be marked dynamically unverified")

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function script(fullType, category, luaCreate)
    return {
        getFullName = function() return fullType end,
        getDisplayCategory = function() return category end,
        getLuaCreate = function() return luaCreate or "" end,
        getReplaceOnUse = function() return "" end,
        getReplaceOnDeplete = function() return "" end,
    }
end

local function source(items, destroy)
    return {
        getItems = function() return javaList(items) end,
        isKeep = function() return false end,
        isDestroy = function() return destroy == true end,
    }
end

local function recipe(moduleName, sources, outputType, outputCount, luaCreate)
    return {
        getModule = function() return { getName = function() return moduleName end } end,
        getSource = function() return javaList(sources) end,
        getResult = function()
            return { getType = function() return outputType end, getCount = function() return outputCount or 1 end }
        end,
        getLuaCreate = function() return luaCreate or "" end,
    }
end

local function manager(scripts, recipes)
    local byType = {}
    for i = 1, #scripts do byType[scripts[i]:getFullName()] = scripts[i] end
    return {
        FindItem = function(_, fullType) return byType[fullType] end,
        getAllItems = function() return javaList(scripts) end,
        getAllRecipes = function() return javaList(recipes or {}) end,
    }
end

currentManager = manager({
    script("CategoryMod.Snack", "Food"),
    script("CategoryMod.Sheet", "Material"),
    script("CategoryMod.Wrench", "Tool"),
    script("CategoryMod.Rifle", "Weapon"),
}, {})
Policy.rebuildTransformIndex(currentManager)
assert(Policy.quote("CategoryMod.Snack").finalBuy == 80, "unknown food must use the food category price")
assert(Policy.quote("CategoryMod.Sheet").finalBuy == 90, "unknown material must use the material category price")
assert(Policy.quote("CategoryMod.Wrench").finalBuy == 220, "unknown tool must use the tool category price")
assert(Policy.quote("CategoryMod.Rifle").finalBuy == 600, "unknown weapon must use the weapon category price")

GodSystemConfig.VanillaItemBuyPrices["RecipeMod.PackedOutput"] = 2000
local packedRecipe = recipe("RecipeMod", { source({ "PackedInput" }) }, "PackedOutput", 4, "")
currentManager = manager({
    script("RecipeMod.PackedInput", "Material"),
    script("RecipeMod.PackedOutput", "Material"),
}, { packedRecipe })
Policy.rebuildTransformIndex(currentManager)
local qualifiedRecipe = Policy.quote("RecipeMod.PackedInput")
assert(qualifiedRecipe.conversionValue == 400, "recipe module objects must qualify unqualified source and result names")
assert(qualifiedRecipe.referenceBuy == 90 and qualifiedRecipe.safeMinimum == 440 and qualifiedRecipe.finalBuy == 440,
    "deterministic conversion value must raise a missing exact price above its category fallback")

local dynamicRecipe = recipe("DynamicMod", { source({ "MysteryBox" }) }, "KnownOutput", 1, "DynamicOpen")
currentManager = manager({
    script("DynamicMod.MysteryBox", "Other"),
    script("DynamicMod.KnownOutput", "Other"),
}, { dynamicRecipe })
Policy.rebuildTransformIndex(currentManager)
local dynamicUnknown = Policy.quote("DynamicMod.MysteryBox")
assert(dynamicUnknown.finalBuy == 550 and dynamicUnknown.dynamicFloor == 550,
    "only a detected one-item dynamic conversion without an exact price must use the 550 risk floor")
assert(dynamicUnknown.verificationStatus == "unverified" and dynamicUnknown.dynamicConversionUnknown == true,
    "detected dynamic conversion must remain visible as unverified")

GodSystemConfig.VanillaItemBuyPrices["DynamicMod.KnownMystery"] = 300
local exactDynamicRecipe = recipe("DynamicMod", { source({ "KnownMystery" }) }, "KnownOutput", 1, "DynamicOpen")
currentManager = manager({
    script("DynamicMod.KnownMystery", "Other"),
    script("DynamicMod.KnownOutput", "Other"),
}, { exactDynamicRecipe })
Policy.rebuildTransformIndex(currentManager)
local dynamicExact = Policy.quote("DynamicMod.KnownMystery")
assert(dynamicExact.finalBuy == 300 and dynamicExact.safeMinimum == 0 and dynamicExact.dynamicFloor == 0,
    "an exact-price dynamic item must keep its configured price instead of receiving the 550 floor")
assert(dynamicExact.verificationStatus == "unverified", "exact-price dynamic items must still show the unverified warning")

local multiRecipe = recipe("MultiMod", { source({ "PartA" }), source({ "PartB" }) }, "Combined", 1, "DynamicCraft")
currentManager = manager({
    script("MultiMod.PartA", "Material"), script("MultiMod.PartB", "Material"), script("MultiMod.Combined", "Material"),
}, { multiRecipe })
Policy.rebuildTransformIndex(currentManager)
local multiInput = Policy.quote("MultiMod.PartA")
assert(multiInput.finalBuy == 90 and multiInput.verificationStatus == "not_applicable",
    "multi-input crafting must not mark each ingredient as a risky unpackable item")

currentManager = manager({ script("CallbackMod.CreatedItem", "Food", "OnCreateCallback") }, {})
Policy.rebuildTransformIndex(currentManager)
local callbackOnly = Policy.quote("CallbackMod.CreatedItem")
assert(callbackOnly.finalBuy == 80 and callbackOnly.verificationStatus == "not_applicable",
    "an item script LuaCreate callback alone must not trigger the dynamic conversion floor")

GodSystemConfig.VanillaItemBuyPrices["Base.PolicyA"] = 20
GodSystemConfig.VanillaItemBuyPrices["Base.PolicyB"] = 10
Policy.setTransformIndexForTests({
    ["Base.PolicyA"] = { { outputs = { { fullType = "Base.PolicyB", count = 2 } } } },
    ["Base.PolicyB"] = { { outputs = { { fullType = "Base.Money", count = 3 } } } },
})
local recursive = Policy.quote("Base.PolicyA")
assert(recursive.conversionValue == 6, "recursive deterministic conversion must reach terminal outputs")
assert(recursive.finalBuy == 20, "existing higher reference price must be preserved")

Policy.setTransformIndexForTests({
    ["Base.PolicyA"] = { { outputs = { { fullType = "Base.PolicyB", count = 1 } } } },
    ["Base.PolicyB"] = { { outputs = { { fullType = "Base.PolicyA", count = 1 } } } },
})
local cycle = Policy.quote("Base.PolicyA")
assert(cycle.finalBuy >= 20 and cycle.finalBuy < 1000000, "conversion cycles must stop without overflow")

local migrated = GodSystemAdminConfig.sanitizeItemOverride({ shopEnabled = false })
assert(migrated.shopMode == "disabled" and migrated.shopEnabled == nil, "legacy shopEnabled=false must migrate to disabled")

local defaults = GodSystemAdminConfig.getSandboxDefaults()
GodSystemAdminConfig.applyRuntime(defaults, {
    ["Base.MoneyBundle"] = { buyPrice = 15, shopMode = "auto" },
})
Policy.rebuildTransformIndex(nil)
local dangerous = Policy.quote("Base.MoneyBundle")
assert(dangerous.finalBuy == 15 and dangerous.safeMinimum == 110, "administrator buy override must remain authoritative")
local warned = false
for i = 1, #dangerous.warnings do
    if dangerous.warnings[i] == "admin_below_safe_minimum" then warned = true end
end
assert(warned, "dangerous administrator price must emit an arbitrage warning")

defaults.RecycleSellPriceMultiplier = 2
GodSystemAdminConfig.applyRuntime(defaults, {})
Policy.rebuildTransformIndex(nil)
local multiplied = Policy.quote("Base.MoneyBundle")
assert(multiplied.conversionValue == 200 and multiplied.safeMinimum == 220, "sell multiplier must invalidate and recalculate the conversion floor")

local item = {
    isBroken = function() return true end,
    getUsedDelta = function() return 0.5 end,
}
local conditioned = Policy.quote("Base.Axe", item)
assert(conditioned.recycleValue >= 1 and conditioned.recycleValue < Policy.quote("Base.Axe").recycleValue, "broken and partially used items must be discounted")

print("Test-GodSystemV422022EconomyRuntime OK")
