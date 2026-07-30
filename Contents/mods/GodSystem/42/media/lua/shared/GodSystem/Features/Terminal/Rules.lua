GodSystemTerminalFeatureRules = GodSystemTerminalFeatureRules or {}

local Rules = GodSystemTerminalFeatureRules

Rules.stateVersion = 1
Rules.terminalFullType = "GodSystem.SystemSpaceTerminal"
Rules.reliefFullType = "GodSystem.SystemTerminalRelief"
Rules.recoveryCosts = {
    { maximumLevel = 3, cost = 10 },
    { maximumLevel = 6, cost = 35 },
    { maximumLevel = 8, cost = 80 },
}
Rules.capacityLevels = {
    { level = 1, value = 10, upgradeCost = 0 },
    { level = 2, value = 15, upgradeCost = 60 },
    { level = 3, value = 20, upgradeCost = 120 },
    { level = 4, value = 25, upgradeCost = 220 },
    { level = 5, value = 30, upgradeCost = 350 },
    { level = 6, value = 35, upgradeCost = 550 },
    { level = 7, value = 42, upgradeCost = 800 },
    { level = 8, value = 49, upgradeCost = 1100 },
}
Rules.reductionLevels = {
    { level = 1, value = 50, upgradeCost = 0 },
    { level = 2, value = 55, upgradeCost = 100 },
    { level = 3, value = 60, upgradeCost = 200 },
    { level = 4, value = 65, upgradeCost = 400 },
    { level = 5, value = 70, upgradeCost = 700 },
    { level = 6, value = 80, upgradeCost = 1100 },
    { level = 7, value = 90, upgradeCost = 1700 },
    { level = 8, value = 99, upgradeCost = 2500 },
}
Rules.reliefPerLevel = 5
Rules.reliefMaxOffset = 2000
Rules.reliefUpgradeCost = 2000

local function finite(value)
    value = tonumber(value)
    if type(value) ~= "number"
        or value ~= value
        or value == math.huge
        or value == -math.huge
    then
        return nil
    end
    return value
end

local function integer(value, fallback)
    value = finite(value)
    if value == nil then return math.floor(tonumber(fallback) or 0) end
    return math.floor(value)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

function Rules.kind(value)
    value = tostring(value or "")
    if value == "capacity" or value == "terminalCapacity" then return "capacity" end
    if value == "reduction" or value == "terminalReduction" then return "reduction" end
    if value == "relief" or value == "terminalRelief" then return "relief" end
    return nil
end

function Rules.maxReliefLevel()
    return math.ceil(Rules.reliefMaxOffset / Rules.reliefPerLevel)
end

function Rules.normalizeState(value)
    value = type(value) == "table" and copy(value) or {}
    value.version = Rules.stateVersion
    value.claimedOnce = value.claimedOnce == true
        or value.autoRecyclerClaimed == true
    value.capacityLevel = clamp(integer(
        value.capacityLevel or value.autoRecyclerCapacityLevel, 1), 1, #Rules.capacityLevels)
    value.reductionLevel = clamp(integer(
        value.reductionLevel or value.autoRecyclerReductionLevel, 1), 1, #Rules.reductionLevels)
    value.reliefLevel = clamp(integer(
        value.reliefLevel or value.autoRecyclerReliefLevel, 0), 0, Rules.maxReliefLevel())
    value.autoRecyclerClaimed = nil
    value.autoRecyclerCapacityLevel = nil
    value.autoRecyclerReductionLevel = nil
    value.autoRecyclerReliefLevel = nil
    return value
end

function Rules.level(state, kind)
    state = Rules.normalizeState(state)
    kind = Rules.kind(kind)
    if kind == "capacity" then return state.capacityLevel end
    if kind == "reduction" then return state.reductionLevel end
    if kind == "relief" then return state.reliefLevel end
    return nil
end

function Rules.value(state, kind)
    state = Rules.normalizeState(state)
    kind = Rules.kind(kind)
    if kind == "capacity" then return Rules.capacityLevels[state.capacityLevel].value end
    if kind == "reduction" then return Rules.reductionLevels[state.reductionLevel].value end
    if kind == "relief" then
        return math.min(Rules.reliefMaxOffset, state.reliefLevel * Rules.reliefPerLevel)
    end
    return nil
end

function Rules.upgradeInfo(state, kind)
    state = Rules.normalizeState(state)
    kind = Rules.kind(kind)
    if not kind then return nil end
    local level = Rules.level(state, kind)
    local maximum = kind == "capacity" and #Rules.capacityLevels
        or kind == "reduction" and #Rules.reductionLevels
        or Rules.maxReliefLevel()
    local nextLevel = level < maximum and level + 1 or nil
    local nextValue, nextCost
    if nextLevel then
        if kind == "capacity" then
            nextValue = Rules.capacityLevels[nextLevel].value
            nextCost = Rules.capacityLevels[nextLevel].upgradeCost
        elseif kind == "reduction" then
            nextValue = Rules.reductionLevels[nextLevel].value
            nextCost = Rules.reductionLevels[nextLevel].upgradeCost
        else
            nextValue = math.min(Rules.reliefMaxOffset, nextLevel * Rules.reliefPerLevel)
            nextCost = Rules.reliefUpgradeCost
        end
    end
    return {
        kind = kind,
        level = level,
        maxLevel = maximum,
        value = Rules.value(state, kind),
        nextLevel = nextLevel,
        nextValue = nextValue,
        nextCost = nextCost,
    }
end

function Rules.advance(state, kind)
    state = Rules.normalizeState(state)
    local info = Rules.upgradeInfo(state, kind)
    if not info then return nil, "upgradeTypeInvalid" end
    if not info.nextLevel then return nil, "upgradeMaxLevel" end
    if info.kind == "capacity" then state.capacityLevel = info.nextLevel
    elseif info.kind == "reduction" then state.reductionLevel = info.nextLevel
    else state.reliefLevel = info.nextLevel end
    return state, nil, info
end

function Rules.recoveryLevel(state)
    state = Rules.normalizeState(state)
    return math.max(state.capacityLevel, state.reductionLevel)
end

function Rules.recoveryCost(state)
    local level = Rules.recoveryLevel(state)
    for index = 1, #Rules.recoveryCosts do
        local row = Rules.recoveryCosts[index]
        if level <= row.maximumLevel then return row.cost end
    end
    return Rules.recoveryCosts[#Rules.recoveryCosts].cost
end

function Rules.spec(state)
    state = Rules.normalizeState(state)
    return {
        terminalFullType = Rules.terminalFullType,
        reliefFullType = Rules.reliefFullType,
        capacityLevel = state.capacityLevel,
        capacity = Rules.value(state, "capacity"),
        reductionLevel = state.reductionLevel,
        reduction = Rules.value(state, "reduction"),
        reliefLevel = state.reliefLevel,
        reliefOffset = Rules.value(state, "relief"),
        reliefActualWeight = -Rules.value(state, "relief"),
        reliefHungChange = Rules.value(state, "relief") / 100,
        reliefCount = state.reliefLevel > 0 and 1 or 0,
    }
end

return Rules
