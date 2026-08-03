local root = assert(arg[1], "repository root is required")
local luaRoot = root .. "/Contents/mods/GodSystem/42/media/lua"

package.path = luaRoot .. "/shared/?.lua;" .. package.path
getScriptManager = nil

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
assert(unknown.safeMinimum == 550 and unknown.finalBuy >= 550, "unknown dynamic item must use the conservative 550 floor")
assert(unknown.verificationStatus == "unverified", "unknown third-party item must be marked unverified")

local function javaList(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local recipeModule = { getName = function() return "RecipeMod" end }
local source = {
    getItems = function() return javaList({ "PackedInput" }) end,
    isKeep = function() return false end,
    isDestroy = function() return false end,
}
local result = {
    getType = function() return "PackedOutput" end,
    getCount = function() return 4 end,
}
local recipe = {
    getModule = function() return recipeModule end,
    getSource = function() return javaList({ source }) end,
    getResult = function() return result end,
    getLuaCreate = function() return "" end,
}
local recipeManager = {
    getAllRecipes = function() return javaList({ recipe }) end,
    getAllItems = function() return javaList({}) end,
}
GodSystemConfig.VanillaItemBuyPrices["RecipeMod.PackedInput"] = 1
GodSystemConfig.VanillaItemBuyPrices["RecipeMod.PackedOutput"] = 100
Policy.rebuildTransformIndex(recipeManager)
local qualifiedRecipe = Policy.quote("RecipeMod.PackedInput")
assert(qualifiedRecipe.conversionValue == 20, "recipe module objects must qualify unqualified source and result names")

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

print("Test-GodSystemV422021EconomyRuntime OK")
