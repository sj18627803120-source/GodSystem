local shared = assert(arg and arg[1], "shared Lua directory argument is required")
shared = string.gsub(shared, "\\", "/")
if string.sub(shared, -1) ~= "/" then shared = shared .. "/" end

GodSystemAdminConfig = {
    getSetting = function(key, fallback) return fallback end,
}
GodSystemConfig = { AttributeXPPerCoin = 10 }
package.preload["GodSystem_Config"] = function() return GodSystemConfig end
package.preload["GodSystem_AdminConfig"] = function() return GodSystemAdminConfig end

dofile(shared .. "GodSystem_CompanionConfig.lua")

local companion = GodSystemCompanionConfig.ensureData({
    unlocked = true,
    unlocks = { attack = true, sight = true, guardian = true },
    resonance = 5,
})
assert(companion.resonance == 5, "existing resonance must be preserved")
for _, id in ipairs(GodSystemCompanionConfig.EffectOrder) do
    assert(companion.effects[id] == false, "new effects must default to locked")
end
assert(GodSystemCompanionConfig.getEffectCost(companion, "shock") == 1000, "shock must unlock first")
assert(GodSystemCompanionConfig.getEffectCost(companion, "corrosion") == nil, "corrosion must wait for shock")
companion.effects.shock = true
assert(GodSystemCompanionConfig.getEffectCost(companion, "corrosion") == 2000, "corrosion cost mismatch")
for id, definition in pairs(GodSystemCompanionConfig.Stats) do
    companion.levels[id] = #definition.values
end
for _, id in ipairs(GodSystemCompanionConfig.EffectOrder) do companion.effects[id] = true end
assert(GodSystemCompanionConfig.areAllEffectsUnlocked(companion), "all effects should be unlocked")
assert(GodSystemCompanionConfig.canPurchaseResonance(companion), "resonance should unlock after stats and effects")
assert(GodSystemCompanionConfig.getResonanceCost(companion) == 5000, "preserved resonance cost mismatch")

local parent = { getName = function() return "Combat" end }
local perk = {}
local factoryPerk = {
    getName = function() return "Mock Skill" end,
    getParent = function() return parent end,
    getTotalXpForLevel = function(_, level) return level * 100 end,
}
Perks = {
    None = {},
    Combat = parent,
    getMaxIndex = function() return 1 end,
    fromIndex = function(index) return index == 0 and perk or nil end,
}
PerkFactory = { getPerk = function(value) return value == perk and factoryPerk or nil end }
local xp = { getXP = function(_, value) return value == perk and 250 or 0 end }
local player = {
    getXp = function() return xp end,
    getPerkLevel = function(_, value) return value == perk and 2 or 0 end,
}

dofile(shared .. "GodSystem_Attributes.lua")
local rows = GodSystemAttributes.enumerate(player)
assert(#rows == 1 and rows[1].label == "Mock Skill", "registered skill enumeration failed")
local amountQuote = assert(GodSystemAttributes.quote(player, 0, "amount", 10, 10))
assert(amountQuote.actualXp == 100 and amountQuote.cost == 10, "amount XP quote mismatch")
local levelQuote = assert(GodSystemAttributes.quote(player, 0, "targetLevel", 4, 10))
assert(levelQuote.actualXp == 150 and levelQuote.cost == 15, "target-level XP quote mismatch")

dofile(shared .. "GodSystem_Maintenance.lua")
local itemTypes = function(empty) return { isEmpty = function() return empty end } end
local parts = {
    { getItemType = function() return itemTypes(false) end, getInventoryItem = function() return {} end, getCondition = function() return 50 end },
    { getItemType = function() return itemTypes(false) end, getInventoryItem = function() return nil end, getCondition = function() return 100 end },
    { getItemType = function() return itemTypes(true) end, getInventoryItem = function() return nil end, getCondition = function() return 100 end },
}
local vehicle = {
    getPartCount = function() return #parts end,
    getPartByIndex = function(_, index) return parts[index + 1] end,
}
local summary = GodSystemMaintenance.vehicleDamageSummary(vehicle)
assert(summary.total == 3 and summary.damaged == 2 and summary.missing == 1, "vehicle damage summary mismatch")

print("Test-GodSystemV11653Runtime passed")
