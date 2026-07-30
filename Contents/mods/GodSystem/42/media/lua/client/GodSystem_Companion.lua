require "GodSystem_CompanionConfig"

GodSystemCompanion = GodSystemCompanion or {}

local Companion = GodSystemCompanion
local Config = GodSystemCompanionConfig

local function companionData()
    if GodSystem and type(GodSystem.getCompanionData) == "function" then
        return GodSystem.getCompanionData()
    end
    return nil
end

local function localized(key, fallback)
    if GodSystem and type(GodSystem.text) == "function" then
        return GodSystem.text(key, fallback)
    end
    return fallback
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if math.floor(value) == value then return tostring(math.floor(value)) end
    return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function nodeRow(id, labelKey, fallback, unlocked, cost,
        detailKey, detailFallback)
    local status = unlocked
        and localized("Companion_StatusUnlocked", "Unlocked")
        or localized("Companion_StatusCost", "Cost") .. " "
            .. tostring(cost or 0) .. localized("Unit_CoinShort", "c")
    return {
        id = id,
        kind = "companionNode",
        label = localized(labelKey, fallback) .. " | " .. status,
        detail = localized(detailKey, detailFallback),
        unlocked = unlocked == true,
        cost = cost,
    }
end

function Companion.getRows()
    local data = companionData()
    if not data then return {} end
    data.unlocks = type(data.unlocks) == "table" and data.unlocks or {}
    data.levels = type(data.levels) == "table" and data.levels or {}
    data.effects = type(data.effects) == "table" and data.effects or {}
    local rows = {
        nodeRow("projection", "Companion_Unlock", "Robot", data.unlocked,
            Config.scaleCost(Config.UnlockCost), "Companion_ProjectionDetail",
            "Unlocks the blue pixel robot, lighting and behavior controls."),
        nodeRow("attack", "Companion_Attack", "Attack", data.unlocks.attack,
            Config.scaleCost(Config.AttackUnlockCost), "Companion_AttackDetail",
            "Unlocks red beam attacks."),
        nodeRow("sight", "Companion_Sight", "Spirit sight", data.unlocks.sight,
            Config.scaleCost(Config.SightUnlockCost), "Companion_SightDetail",
            "Marks nearby zombies and permits attacks through walls."),
        nodeRow("guardian", "Companion_Guardian", "Guardian",
            data.unlocks.guardian, Config.scaleCost(Config.GuardianUnlockCost),
            "Companion_GuardianDetail",
            "Knocks down nearby zombies when one enters the danger radius."),
    }
    for _, id in ipairs(Config.StatOrder) do
        local definition = Config.Stats[id]
        local level = data.levels[id] or 1
        local current = Config.getStatValue(data, id)
        local nextValue = definition.values[level + 1]
        local cost = Config.getUpgradeCost(data, id)
        local label = localized(definition.labelKey, id) .. " Lv."
            .. tostring(level)
        local detail = localized("Companion_Current", "Current") .. ": "
            .. formatNumber(current)
        if nextValue then
            label = label .. " | " .. tostring(cost)
                .. localized("Unit_CoinShort", "c")
            detail = detail .. "  ->  " .. formatNumber(nextValue)
        else
            label = label .. " | " .. localized("Upgrade_Maxed", "Maxed")
        end
        rows[#rows + 1] = {
            id = id,
            kind = "companionNode",
            label = label,
            detail = detail,
            unlocked = Config.isUnlocked(data, definition.requires),
            maxed = nextValue == nil,
            cost = cost,
        }
    end
    for _, id in ipairs(Config.EffectOrder) do
        local definition = Config.Effects[id]
        local owned = Config.isEffectUnlocked(data, id)
        local cost = Config.getEffectCost(data, id)
        local status
        if owned then
            status = localized("Companion_StatusUnlocked", "Unlocked")
        elseif cost then
            status = localized("Companion_StatusCost", "Cost") .. " "
                .. tostring(cost) .. localized("Unit_CoinShort", "c")
        else
            status = localized("Companion_EffectRequiresPrevious",
                "Unlock the previous effect first")
        end
        rows[#rows + 1] = {
            id = id,
            kind = "companionNode",
            label = localized(definition.labelKey, id) .. " | " .. status,
            detail = localized(definition.detailKey, id),
            unlocked = owned or cost ~= nil,
            maxed = owned,
            cost = cost,
            companionEffect = true,
        }
    end
    local resonanceCost = Config.getResonanceCost(data)
    rows[#rows + 1] = {
        id = "resonance",
        kind = "companionNode",
        label = localized("Companion_Resonance", "Resonance") .. " Lv."
            .. tostring(data.resonance or 0) .. " | "
            .. (resonanceCost
                and (tostring(resonanceCost) .. localized("Unit_CoinShort", "c"))
                or localized("Companion_ResonanceLockedShort", "Locked")),
        detail = localized("Companion_ResonanceDetail",
            "Each level increases final attack damage by 1% after all functional upgrades and attack effects are unlocked."),
        unlocked = Config.canPurchaseResonance(data),
        cost = resonanceCost,
    }
    return rows
end

function Companion.getStateDetail()
    local data = companionData()
    if not data then return "" end
    local combat = localized("Companion_Mode_" .. tostring(data.combatMode),
        tostring(data.combatMode))
    local follow = localized("Companion_Mode_" .. tostring(data.followMode),
        tostring(data.followMode))
    local visible = data.visible
        and localized("Companion_Visible", "Visible")
        or localized("Companion_Hidden", "Hidden")
    return localized("Companion_State", "State") .. ": "
        .. localized("Companion_Robot", "Blue pixel robot") .. " | "
        .. combat .. " | " .. follow .. " | " .. visible
end

return Companion
