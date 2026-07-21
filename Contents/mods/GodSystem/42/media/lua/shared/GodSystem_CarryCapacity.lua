require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}
GodSystemCarryCapacity.runtime = GodSystemCarryCapacity.runtime or {}

local MARKER_BONUS = "GodSystemCarryAppliedBonus"
local MARKER_DELTA = "GodSystemCarryAppliedDelta"
local MARKER_FACTOR = "GodSystemCarryAppliedFactor"
local MARKER_BASELINE = "GodSystemCarryBaseline"
local EPSILON = 0.001
local FINAL_EPSILON = 0.01
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

local function readBase(player)
    if not player or not player.getMaxWeightBase then return nil end
    local ok, value = pcall(function() return player:getMaxWeightBase() end)
    value = ok and tonumber(value) or nil
    if not finite(value) or value <= 0 then return nil end
    return value
end

local function readFinal(player)
    if not player or not player.getMaxWeight then return nil end
    local ok, value = pcall(function() return player:getMaxWeight() end)
    value = ok and tonumber(value) or nil
    if not finite(value) then return nil end
    return value
end

local function writeFinal(player, value)
    value = tonumber(value)
    if not player or not player.setMaxWeight or not finite(value) then return false end
    value = math.max(0, math.floor(value + EPSILON))
    local ok = pcall(function() player:setMaxWeight(value) end)
    if not ok then return false end
    local after = readFinal(player)
    return after ~= nil and math.abs(after - value) <= FINAL_EPSILON, after
end

local function capacityFromDelta(maxWeightBase, delta, modelOffset)
    local raw = tonumber(maxWeightBase) * (tonumber(delta) + tonumber(modelOffset))
    if not finite(raw) or math.abs(raw) > SAFE_INTEGER then return nil end
    return math.max(0, math.ceil(raw))
end

local function detectDeltaModel(maxWeightBase, delta, finalWeight)
    local additive = capacityFromDelta(maxWeightBase, delta, 1)
    local multiplier = capacityFromDelta(maxWeightBase, delta, 0)
    if additive == nil then return multiplier ~= nil and 0 or nil end
    if multiplier == nil then return 1 end
    if math.abs(additive - finalWeight) <= math.abs(multiplier - finalWeight) then return 1 end
    return 0
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
    local desiredBonus = GodSystemCarryCapacity.getBonus(level)
    local current = readDelta(player)
    local maxWeightBase = readBase(player)
    if desiredBonus == nil then return false, "overflow" end
    local originalFinal = readFinal(player)
    if current == nil or maxWeightBase == nil or originalFinal == nil then return false, "unsupported" end
    local modelOffset = detectDeltaModel(maxWeightBase, current, originalFinal)
    if modelOffset == nil then return false, "unsupported" end

    local state = GodSystemCarryCapacity.runtime[player]
    local previousFactor = 0
    if state and finite(tonumber(state.appliedFactor)) then
        previousFactor = tonumber(state.appliedFactor)
    else
        local modData = playerModData(player)
        local markerBonus = modData and tonumber(modData[MARKER_BONUS]) or nil
        local markerDelta = modData and tonumber(modData[MARKER_DELTA]) or nil
        local markerFactor = modData and tonumber(modData[MARKER_FACTOR]) or nil
        if finite(markerFactor) and finite(markerDelta) and math.abs(current - markerDelta) <= EPSILON then
            previousFactor = markerFactor
        elseif finite(markerBonus) and finite(markerDelta) and math.abs(current - markerDelta) <= EPSILON then
            -- v1.16.57 originally wrote the carry-unit bonus directly as a multiplier.
            previousFactor = markerBonus
        end
    end

    local externalDelta = current - previousFactor
    if not finite(externalDelta) or math.abs(externalDelta) > SAFE_INTEGER then return false, "overflow" end

    -- Preserve the v1.16.59 application behavior.  The model helpers above
    -- are read-only measurement support for UI reporting; they do not change
    -- the configured carry contribution or its written delta.
    local baselineWritten = writeDelta(player, externalDelta)
    if not baselineWritten then
        writeDelta(player, current)
        return false, "baselineFailed"
    end

    local writeBaseline = math.max(0, math.floor(maxWeightBase * (1 + externalDelta) + EPSILON))
    local measuredBaseline = capacityFromDelta(maxWeightBase, externalDelta, modelOffset) or writeBaseline
    local desiredFactor = desiredBonus / maxWeightBase
    local target = externalDelta + desiredFactor
    local desiredFinal = writeBaseline + desiredBonus
    if not finite(desiredFinal) or desiredFinal > SAFE_INTEGER then
        writeDelta(player, current)
        return false, "overflow"
    end
    if not finite(target) or math.abs(target) > SAFE_INTEGER then
        writeDelta(player, current)
        return false, "overflow"
    end

    local ok, after = writeDelta(player, target)
    if not ok then
        writeDelta(player, current)
        writeFinal(player, originalFinal)
        return false, "writeFailed"
    end

    local finalWritten, actualFinal = writeFinal(player, desiredFinal)
    if not finalWritten then
        writeDelta(player, current)
        writeFinal(player, originalFinal)
        return false, "verificationFailed"
    end

    local predictedFinal = capacityFromDelta(maxWeightBase, after or target, modelOffset)
    local predictedIncrease = predictedFinal and (predictedFinal - originalFinal) or nil
    local appliedFactor = target - externalDelta
    GodSystemCarryCapacity.runtime[player] = {
        appliedBonus = desiredBonus,
        appliedFactor = appliedFactor,
        delta = after or target,
        externalDelta = externalDelta,
        baseline = measuredBaseline,
        modelOffset = modelOffset,
        predictedFinal = predictedFinal,
        predictedIncrease = predictedIncrease,
        level = level,
    }
    local modData = playerModData(player)
    if modData then
        modData[MARKER_BONUS] = desiredBonus
        modData[MARKER_DELTA] = after or target
        modData[MARKER_FACTOR] = appliedFactor
        modData[MARKER_BASELINE] = measuredBaseline
    end
    return true, GodSystemCarryCapacity.getStatus(player, level)
end

function GodSystemCarryCapacity.getStatus(player, level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local desired = GodSystemCarryCapacity.getBonus(level) or 0
    local delta = readDelta(player)
    local total = readFinal(player)

    local applied = 0
    local baseline = nil
    local predictedFinal = nil
    local predictedIncrease = nil
    local state = player and GodSystemCarryCapacity.runtime[player] or nil
    if state and finite(tonumber(state.appliedBonus)) then
        applied = math.max(0, tonumber(state.appliedBonus))
        baseline = finite(tonumber(state.baseline)) and tonumber(state.baseline) or nil
        predictedFinal = finite(tonumber(state.predictedFinal)) and tonumber(state.predictedFinal) or nil
        predictedIncrease = finite(tonumber(state.predictedIncrease)) and tonumber(state.predictedIncrease) or nil
    elseif player then
        local modData = playerModData(player)
        local markerBonus = modData and tonumber(modData[MARKER_BONUS]) or nil
        local markerDelta = modData and tonumber(modData[MARKER_DELTA]) or nil
        if finite(markerBonus) and finite(markerDelta) and delta and math.abs(delta - markerDelta) <= EPSILON then
            applied = math.max(0, markerBonus)
            local markerBaseline = tonumber(modData[MARKER_BASELINE])
            baseline = finite(markerBaseline) and markerBaseline or nil
        end
    end

    local base = baseline or (total and (total - applied) or nil)
    local actualBonus = total ~= nil and base ~= nil and (total - base) or nil
    return {
        level = level,
        bonus = desired,
        appliedBonus = applied,
        actualBonus = actualBonus,
        base = base,
        total = total,
        delta = delta,
        predictedFinal = predictedFinal,
        predictedIncrease = predictedIncrease,
        applied = math.abs(applied - desired) <= EPSILON and total ~= nil and base ~= nil,
    }
end
