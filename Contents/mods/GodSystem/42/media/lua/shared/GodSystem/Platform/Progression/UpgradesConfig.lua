require "GodSystem/Platform/Progression/Support"

GodSystemUpgradesConfigPlatform = GodSystemUpgradesConfigPlatform or {}

local Descriptor = GodSystemUpgradesConfigPlatform
local Support = GodSystemProgressionPlatformSupport

Descriptor.id = "upgrades.config"
Descriptor.dependencies = {}
Descriptor.stateVersion = 1

local DEFAULTS = {
    MaxActiveTaskLimit = 10,
    MaxDailyTaskLimit = 20,
    ActiveTaskUpgradeCosts = {
        [4] = 100, [5] = 150, [6] = 220, [7] = 300,
        [8] = 420, [9] = 560, [10] = 750,
    },
    DailyTaskUpgradeCosts = {
        [6] = 50, [7] = 60, [8] = 70, [9] = 85, [10] = 100,
        [11] = 120, [12] = 145, [13] = 170, [14] = 200, [15] = 230,
        [16] = 260, [17] = 300, [18] = 340, [19] = 380, [20] = 420,
    },
    CarryCapacityBaseCost = 2000,
    CarryCapacityCostMultiplier = 1.5,
    TerminalCapacityLevels = {
        { level = 1, value = 10, upgradeCost = 0 },
        { level = 2, value = 15, upgradeCost = 60 },
        { level = 3, value = 20, upgradeCost = 120 },
        { level = 4, value = 25, upgradeCost = 220 },
        { level = 5, value = 30, upgradeCost = 350 },
        { level = 6, value = 35, upgradeCost = 550 },
        { level = 7, value = 42, upgradeCost = 800 },
        { level = 8, value = 49, upgradeCost = 1100 },
    },
    TerminalReductionLevels = {
        { level = 1, value = 50, upgradeCost = 0 },
        { level = 2, value = 55, upgradeCost = 100 },
        { level = 3, value = 60, upgradeCost = 200 },
        { level = 4, value = 65, upgradeCost = 400 },
        { level = 5, value = 70, upgradeCost = 700 },
        { level = 6, value = 80, upgradeCost = 1100 },
        { level = 7, value = 90, upgradeCost = 1700 },
        { level = 8, value = 99, upgradeCost = 2500 },
    },
    TerminalReliefUpgradeCost = 2000,
    TerminalReliefPerLevel = 5,
    TerminalReliefMaxOffset = 2000,
}

function Descriptor.create(_, context)
    local config = Support.config(context, DEFAULTS)
    local counters = { quotes = 0, rejected = 0 }
    local public = {}

    local function rowQuote(rows, current)
        current = Support.integer(current, nil, 1)
        local nextRow = current and type(rows) == "table" and rows[current + 1] or nil
        local cost = nextRow and Support.integer(nextRow.upgradeCost, nil, 0) or nil
        if cost == nil then return nil, "upgradeMaxed" end
        return { nextValue = current + 1, cost = cost, value = nextRow.value }
    end

    function public.quote(_, upgradeType, current)
        counters.quotes = counters.quotes + 1
        current = Support.integer(current, nil, 0)
        if current == nil then
            counters.rejected = counters.rejected + 1
            return nil, "levelInvalid"
        end
        if upgradeType == "carryCapacity" then
            local base = Support.number(config.CarryCapacityBaseCost, nil, 1)
            local multiplier = Support.number(config.CarryCapacityCostMultiplier, nil, 1)
            local raw = base and multiplier and base * (multiplier ^ current) or nil
            local cost = Support.integer(raw and math.ceil(raw), nil, 1)
            if cost == nil then return nil, "upgradeMaxed" end
            return { nextValue = current + 1, cost = cost }
        end
        if upgradeType == "activeTasks" then
            local maximum = Support.integer(config.MaxActiveTaskLimit, 10, 1)
            if current >= maximum then return nil, "upgradeMaxed" end
            local nextValue = current + 1
            local cost = Support.integer(config.ActiveTaskUpgradeCosts[nextValue], nil, 0)
            return cost and { nextValue = nextValue, cost = cost } or nil, cost and nil or "quoteMissing"
        end
        if upgradeType == "dailyTasks" then
            local maximum = Support.integer(config.MaxDailyTaskLimit, 20, 1)
            if current >= maximum then return nil, "upgradeMaxed" end
            local nextValue = current + 1
            local cost = Support.integer(config.DailyTaskUpgradeCosts[nextValue], nil, 0)
            return cost and { nextValue = nextValue, cost = cost } or nil, cost and nil or "quoteMissing"
        end
        if upgradeType == "terminalCapacity" then return rowQuote(config.TerminalCapacityLevels, current) end
        if upgradeType == "terminalReduction" then return rowQuote(config.TerminalReductionLevels, current) end
        if upgradeType == "terminalRelief" then
            local perLevel = Support.integer(config.TerminalReliefPerLevel, 5, 1)
            local maximum = Support.integer(config.TerminalReliefMaxOffset, 2000, 0)
            local maxLevel = math.ceil(maximum / perLevel)
            if current >= maxLevel then return nil, "upgradeMaxed" end
            return {
                nextValue = current + 1,
                cost = Support.integer(config.TerminalReliefUpgradeCost, 2000, 0),
                value = math.min(maximum, (current + 1) * perLevel),
            }
        end
        counters.rejected = counters.rejected + 1
        return nil, "upgradeTypeInvalid"
    end

    return Support.lifecycle(Descriptor.id, public, counters)
end

return Descriptor
