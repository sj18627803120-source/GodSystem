require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}
GodSystemCarryCapacity.runtime = GodSystemCarryCapacity.runtime or {}

local MARKER_BONUS = "GodSystemCarryAppliedBonus"
local MARKER_DELTA = "GodSystemCarryAppliedDelta"
local EPSILON = 0.001
local SAFE_INTEGER = 9007199254740991

local function finite(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function playerModData(player)
    if not player or not player.getModData then return nil end
    local ok, data = pcall(function() return player:getModData() end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function readDelta(player)
    if not player or not player.getMaxWeightDelta then return nil end
    local ok, value = pcall(function() return player:getMaxWeightDelta() end)
    value = ok and tonumber(value) or nil
    if not finite(value) then return nil end
    return value
end

local function writeDelta(player, value)
    if not player or not player.setMaxWeightDelta or not finite(value) then return false end
    local ok = pcall(function() player:setMaxWeightDelta(value) end)
    if not ok then return false end
    local after = readDelta(player)
    return after ~= nil and math.abs(after - value) <= EPSILON, after
end

function GodSystemCarryCapacity.normalizeLevel(value)
    value = tonumber(value)
    if not finite(value) then return 0 end
    value = math.floor(value)
    if value < 0 then return 0 end
    if value > math.floor(SAFE_INTEGER / 2) then return math.floor(SAFE_INTEGER / 2) end
    return value
end

function GodSystemCarryCapacity.getBonus(level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local bonus = level * math.max(0, tonumber(GodSystemConfig.CarryCapacityPerLevel) or 2)
    if not finite(bonus) or bonus > SAFE_INTEGER then return nil end
    return bonus
end

function GodSystemCarryCapacity.getNextCost(level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local base = math.max(1, tonumber(GodSystemConfig.CarryCapacityBaseCost) or 2000)
    local multiplier = math.max(1, tonumber(GodSystemConfig.CarryCapacityCostMultiplier) or 1.5)
    local raw = base * (multiplier ^ level)
    if not finite(raw) or raw > SAFE_INTEGER then return nil end
    local cost = math.ceil(raw)
    if not finite(cost) or cost < 1 or cost > SAFE_INTEGER then return nil end
    return cost
end

function GodSystemCarryCapacity.getLevel(data)
    local upgrades = data and data.upgrades or nil
    return GodSystemCarryCapacity.normalizeLevel(upgrades and upgrades.carryCapacityLevel or 0)
end

function GodSystemCarryCapacity.clearRuntime(player)
    if player then
        GodSystemCarryCapacity.runtime[player] = nil
    else
        GodSystemCarryCapacity.runtime = {}
    end
end

function GodSystemCarryCapacity.apply(player, level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local desired = GodSystemCarryCapacity.getBonus(level)
    local current = readDelta(player)
    if desired == nil then return false, "overflow" end
    if current == nil then return false, "unsupported" end

    local state = GodSystemCarryCapacity.runtime[player]
    local previous = 0
    if state and finite(tonumber(state.applied)) then
        previous = tonumber(state.applied)
        if current < previous and finite(tonumber(state.externalDelta)) and tonumber(state.externalDelta) >= 0 then
            previous = 0
        end
    else
        local modData = playerModData(player)
        local markerBonus = modData and tonumber(modData[MARKER_BONUS]) or nil
        local markerDelta = modData and tonumber(modData[MARKER_DELTA]) or nil
        if finite(markerBonus) and finite(markerDelta) and math.abs(current - markerDelta) <= EPSILON then
            previous = math.max(0, markerBonus)
        end
    end

    local externalDelta = current - previous
    local target = externalDelta + desired
    if not finite(target) or math.abs(target) > SAFE_INTEGER then return false, "overflow" end

    local ok, after = writeDelta(player, target)
    if not ok then
        writeDelta(player, current)
        return false, "writeFailed"
    end

    GodSystemCarryCapacity.runtime[player] = {
        applied = desired,
        delta = after or target,
        externalDelta = externalDelta,
        level = level,
    }
    local modData = playerModData(player)
    if modData then
        modData[MARKER_BONUS] = desired
        modData[MARKER_DELTA] = after or target
    end
    return true, GodSystemCarryCapacity.getStatus(player, level)
end

function GodSystemCarryCapacity.getStatus(player, level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local desired = GodSystemCarryCapacity.getBonus(level) or 0
    local delta = readDelta(player)
    local total = nil
    if player and player.getMaxWeight then
        local ok, value = pcall(function() return player:getMaxWeight() end)
        value = ok and tonumber(value) or nil
        if finite(value) then total = value end
    end

    local applied = 0
    local state = player and GodSystemCarryCapacity.runtime[player] or nil
    if state and finite(tonumber(state.applied)) then
        applied = math.max(0, tonumber(state.applied))
    elseif player then
        local modData = playerModData(player)
        local markerBonus = modData and tonumber(modData[MARKER_BONUS]) or nil
        local markerDelta = modData and tonumber(modData[MARKER_DELTA]) or nil
        if finite(markerBonus) and finite(markerDelta) and delta and math.abs(delta - markerDelta) <= EPSILON then
            applied = math.max(0, markerBonus)
        end
    end

    local base = total and (total - applied) or nil
    return {
        level = level,
        bonus = desired,
        appliedBonus = applied,
        base = base,
        total = total,
        delta = delta,
        applied = math.abs(applied - desired) <= EPSILON,
    }
end
