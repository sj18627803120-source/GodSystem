require "GodSystem_Config"

GodSystemCarryCapacity = GodSystemCarryCapacity or {}
GodSystemCarryCapacity.runtime = GodSystemCarryCapacity.runtime or {}

local MARKER_BONUS = "GodSystemCarryAppliedBonus"
local MARKER_DELTA = "GodSystemCarryAppliedDelta"
local MARKER_FACTOR = "GodSystemCarryAppliedFactor"
local MARKER_BASELINE = "GodSystemCarryBaseline"
local MARKER_NATIVE_DELTA = "GodSystemCarryNativeDelta"
local EPSILON = 0.001
local FINAL_EPSILON = 0.01
local SAFE_INTEGER = 9007199254740991

local STRENGTH_MOODLES = {
    { name = "HUNGRY", reducers = { [2] = 1, [3] = 2, [4] = 2 } },
    { name = "THIRST", reducers = { [2] = 1, [3] = 2, [4] = 2 } },
    { name = "SICK", reducers = { [2] = 1, [3] = 2, [4] = 3 } },
    { name = "BLEEDING", reducers = { [2] = 1, [3] = 1, [4] = 1 } },
    { name = "INJURED", reducers = { [2] = 1, [3] = 2, [4] = 3 } },
}

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

local function readWeightMod(player)
    if not player or not player.getWeightMod then return nil end
    local ok, value = pcall(function() return player:getWeightMod() end)
    value = ok and tonumber(value) or nil
    if not finite(value) or value < 0 then return nil end
    return value
end

local function readMoodleLevel(player, name)
    if not player or not player.getMoodles or not MoodleType then return nil end
    local moodleType = MoodleType[name]
    if moodleType == nil then return nil end
    local okMoodles, moodles = pcall(function() return player:getMoodles() end)
    if not okMoodles or not moodles or not moodles.getMoodleLevel then return nil end
    local okLevel, value = pcall(function() return moodles:getMoodleLevel(moodleType) end)
    value = okLevel and tonumber(value) or nil
    if not finite(value) then return nil end
    return math.max(0, math.floor(value))
end

local function readStrengthReducers(player)
    local reducers = 0
    for i = 1, #STRENGTH_MOODLES do
        local definition = STRENGTH_MOODLES[i]
        local level = readMoodleLevel(player, definition.name)
        if level == nil then return nil end
        reducers = reducers + (definition.reducers[level] or 0)
    end
    return reducers
end

function GodSystemCarryCapacity.getVanillaCapacity(player)
    local maxWeightBase = readBase(player)
    local weightMod = readWeightMod(player)
    local reducers = readStrengthReducers(player)
    if maxWeightBase == nil or weightMod == nil or reducers == nil then return nil end
    local capacity = math.floor(maxWeightBase * weightMod + EPSILON) - reducers
    return math.max(0, capacity)
end

local function vanillaFinal(player, nativeDelta)
    local capacity = GodSystemCarryCapacity.getVanillaCapacity(player)
    nativeDelta = tonumber(nativeDelta)
    if capacity == nil or not finite(nativeDelta) then return nil end
    return math.max(0, math.floor(capacity * nativeDelta + EPSILON))
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

local function resolveNativeContext(player, currentDelta)
    local state = player and GodSystemCarryCapacity.runtime[player] or nil
    local modData = playerModData(player)
    local appliedDelta = state and tonumber(state.appliedDelta) or nil
    local appliedFactor = state and tonumber(state.appliedFactor) or nil
    local nativeDelta = state and tonumber(state.nativeDelta) or nil
    local appliedBonus = state and tonumber(state.appliedBonus) or nil
    if modData then
        appliedDelta = appliedDelta or tonumber(modData[MARKER_DELTA])
        appliedFactor = appliedFactor or tonumber(modData[MARKER_FACTOR])
        nativeDelta = nativeDelta or tonumber(modData[MARKER_NATIVE_DELTA])
        appliedBonus = appliedBonus or tonumber(modData[MARKER_BONUS])
    end
    if finite(appliedDelta) and math.abs(currentDelta - appliedDelta) <= EPSILON then
        if not finite(nativeDelta) and finite(appliedFactor) then
            nativeDelta = currentDelta - appliedFactor
        end
        if not finite(nativeDelta) and finite(appliedBonus) then
            -- Legacy v1.16.57 markers stored the carry bonus as a multiplier.
            nativeDelta = currentDelta - appliedBonus
        end
        if finite(nativeDelta) then
            return nativeDelta, math.max(0, appliedBonus or 0), true
        end
    end
    return currentDelta, 0, false
end

function GodSystemCarryCapacity.apply(player, level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local desiredBonus = GodSystemCarryCapacity.getBonus(level)
    local current = readDelta(player)
    local originalFinal = readFinal(player)
    if desiredBonus == nil then return false, "overflow" end
    if current == nil or originalFinal == nil then return false, "unsupported" end

    local nativeDelta = resolveNativeContext(player, current)
    local nativeCapacity = GodSystemCarryCapacity.getVanillaCapacity(player)
    local nativeFinal = vanillaFinal(player, nativeDelta)
    if nativeCapacity == nil or nativeCapacity <= 0 or nativeFinal == nil then return false, "unsupported" end

    local desiredFinal = nativeFinal + desiredBonus
    local target = desiredFinal / nativeCapacity
    if not finite(desiredFinal) or desiredFinal > SAFE_INTEGER or not finite(target) or math.abs(target) > SAFE_INTEGER then
        writeDelta(player, current)
        return false, "overflow"
    end

    local ok, after = writeDelta(player, target)
    if not ok then
        writeDelta(player, current)
        writeFinal(player, originalFinal)
        return false, "writeFailed"
    end

    local finalWritten = writeFinal(player, desiredFinal)
    if not finalWritten then
        writeDelta(player, current)
        writeFinal(player, originalFinal)
        return false, "verificationFailed"
    end

    local appliedFactor = target - nativeDelta
    GodSystemCarryCapacity.runtime[player] = {
        appliedBonus = desiredBonus,
        appliedFactor = appliedFactor,
        delta = after or target,
        appliedDelta = after or target,
        nativeDelta = nativeDelta,
        nativeFinal = nativeFinal,
        baseline = nativeFinal,
        predictedFinal = desiredFinal,
        predictedIncrease = desiredFinal - originalFinal,
        level = level,
    }
    local modData = playerModData(player)
    if modData then
        modData[MARKER_BONUS] = desiredBonus
        modData[MARKER_DELTA] = after or target
        modData[MARKER_FACTOR] = appliedFactor
        modData[MARKER_BASELINE] = nativeFinal
        modData[MARKER_NATIVE_DELTA] = nativeDelta
    end
    return true, GodSystemCarryCapacity.getStatus(player, level)
end

function GodSystemCarryCapacity.reconcile(player, level)
    return GodSystemCarryCapacity.apply(player, level)
end

function GodSystemCarryCapacity.getStatus(player, level)
    level = GodSystemCarryCapacity.normalizeLevel(level)
    local desired = GodSystemCarryCapacity.getBonus(level) or 0
    local delta = readDelta(player)
    local total = readFinal(player)
    local applied = 0
    local base = nil
    local predictedFinal = nil
    local predictedIncrease = nil
    local matched = false
    if player and delta ~= nil then
        local nativeDelta, markerBonus, hasApplied = resolveNativeContext(player, delta)
        base = vanillaFinal(player, nativeDelta)
        if hasApplied then
            applied = markerBonus
            matched = true
            local state = GodSystemCarryCapacity.runtime[player]
            if state then
                predictedFinal = tonumber(state.predictedFinal)
                predictedIncrease = tonumber(state.predictedIncrease)
            end
        end
    end
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
        applied = matched and math.abs((actualBonus or 0) - desired) <= FINAL_EPSILON,
    }
end
