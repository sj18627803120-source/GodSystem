require "GodSystem_Config"
require "GodSystem_TerminalRelief"
require "GodSystem_TerminalFood"
require "GodSystem_B42JavaCalls"

GodSystemTerminalUpgrades = GodSystemTerminalUpgrades or {}

local EPSILON = 0.0001

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function itemModData(item)
    if not item or not item.getModData then return nil end
    local ok, data = pcall(function() return item:getModData() end)
    return ok and type(data) == "table" and data or nil
end

local function readNumberMethod(target, method)
    local value = nil
    if method == "getCapacity" then
        value = GodSystemB42JavaCalls.getCapacity(target)
    elseif method == "getWeightReduction" then
        value = GodSystemB42JavaCalls.getWeightReduction(target)
    end
    value = tonumber(value)
    return finite(value) and value or nil
end

local function writeNumberMethod(target, setter, getter, value)
    local writer = nil
    if setter == "setCapacity" and getter == "getCapacity" then
        writer = GodSystemB42JavaCalls.setCapacity
    elseif setter == "setWeightReduction" and getter == "getWeightReduction" then
        writer = GodSystemB42JavaCalls.setWeightReduction
    else
        return false, false, "unsupported"
    end
    local before = readNumberMethod(target, getter)
    if before == nil then return false, false, "readFailed" end
    if math.abs(before - value) <= EPSILON then return true, false end
    local ok = writer(target, value)
    if not ok then return false, false, "writeException" end
    local after = readNumberMethod(target, getter)
    if after == nil or math.abs(after - value) > EPSILON then return false, false, "verificationFailed" end
    return true, true
end

local function writeTableValue(target, key, value)
    if not target or target[key] == value then return false end
    target[key] = value
    return true
end

local function normalizeLevel(value, maximum)
    value = math.floor(tonumber(value) or 1)
    return math.max(1, math.min(value, math.max(1, maximum or 1)))
end

local function upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" or upgradeType == "terminalCapacity" then return "capacity" end
    if upgradeType == "reduction" or upgradeType == "terminalReduction" then return "reduction" end
    if upgradeType == "relief" or upgradeType == "terminalRelief" then return "relief" end
    if upgradeType == "freshness" or upgradeType == "terminalFreshness" then return "freshness" end
    return nil
end

function GodSystemTerminalUpgrades.getLevels(upgradeType)
    upgradeType = upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" then return GodSystemConfig.TerminalCapacityLevels or {} end
    if upgradeType == "reduction" then return GodSystemConfig.TerminalReductionLevels or {} end
    if upgradeType == "freshness" then return GodSystemConfig.TerminalFreshnessLevels or {} end
    return {}
end

function GodSystemTerminalUpgrades.getField(upgradeType)
    upgradeType = upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" then return "autoRecyclerCapacityLevel" end
    if upgradeType == "reduction" then return "autoRecyclerReductionLevel" end
    if upgradeType == "relief" then return "autoRecyclerReliefLevel" end
    return nil
end

function GodSystemTerminalUpgrades.normalizeData(data)
    if type(data) ~= "table" then return data end
    local capacityLevels = GodSystemTerminalUpgrades.getLevels("capacity")
    local reductionLevels = GodSystemTerminalUpgrades.getLevels("reduction")
    if data.autoRecyclerCapacityLevel == nil then data.autoRecyclerCapacityLevel = 1 end
    if data.autoRecyclerReductionLevel == nil then data.autoRecyclerReductionLevel = 1 end
    data.autoRecyclerCapacityLevel = normalizeLevel(data.autoRecyclerCapacityLevel, #capacityLevels)
    data.autoRecyclerReductionLevel = normalizeLevel(data.autoRecyclerReductionLevel, #reductionLevels)
    GodSystemTerminalRelief.getLevel(data)
    GodSystemTerminalFood.normalizeData(data)
    return data
end

function GodSystemTerminalUpgrades.getLevel(data, upgradeType)
    GodSystemTerminalUpgrades.normalizeData(data)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then return GodSystemTerminalRelief.getLevel(data) end
    if key == "freshness" then return GodSystemTerminalFood.getFreshnessLevel(data) end
    local field = GodSystemTerminalUpgrades.getField(key)
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    return field and normalizeLevel(data and data[field], #levels) or 1
end

function GodSystemTerminalUpgrades.setLevel(data, upgradeType, level)
    GodSystemTerminalUpgrades.normalizeData(data)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then return GodSystemTerminalRelief.setLevel(data, level) end
    if key == "freshness" then return GodSystemTerminalFood.setFreshnessLevel(data, level) end
    local field = GodSystemTerminalUpgrades.getField(key)
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    if not field or #levels <= 0 then return false end
    data[field] = normalizeLevel(level, #levels)
    return true
end

function GodSystemTerminalUpgrades.getLevelData(data, upgradeType, level)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then
        local info = GodSystemTerminalRelief.getUpgradeInfo(data)
        return { level = info.level, value = info.offset, upgradeCost = info.nextCost or 0 }
    end
    if key == "freshness" then
        local info = GodSystemTerminalFood.getFreshnessInfo(data)
        return { level = info.level, value = info.restorePerDay, upgradeCost = info.nextCost or 0 }
    end
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    level = normalizeLevel(level or GodSystemTerminalUpgrades.getLevel(data, key), #levels)
    return levels[level] or levels[1] or { level = 1, value = 0, upgradeCost = 0 }
end

function GodSystemTerminalUpgrades.getUpgradeInfo(data, upgradeType)
    local key = upgradeTypeKey(upgradeType)
    if not key then return nil end
    if key == "relief" then return GodSystemTerminalRelief.getUpgradeInfo(data) end
    if key == "freshness" then
        local info = GodSystemTerminalFood.getFreshnessInfo(data)
        return {
            upgradeType = key,
            level = info.level,
            maxLevel = info.maxLevel,
            value = info.restorePerDay,
            nextValue = info.nextRestorePerDay,
            nextCost = info.nextCost,
        }
    end
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    local level = GodSystemTerminalUpgrades.getLevel(data, key)
    local current = GodSystemTerminalUpgrades.getLevelData(data, key, level)
    local nextRow = level < #levels and levels[level + 1] or nil
    return {
        upgradeType = key,
        level = level,
        maxLevel = #levels,
        value = tonumber(current.value) or 0,
        nextValue = nextRow and (tonumber(nextRow.value) or 0) or nil,
        nextCost = nextRow and math.max(0, math.floor(tonumber(nextRow.upgradeCost) or 0)) or nil,
    }
end

function GodSystemTerminalUpgrades.getRecoveryLevel(data)
    return math.max(
        GodSystemTerminalUpgrades.getLevel(data, "capacity"),
        GodSystemTerminalUpgrades.getLevel(data, "reduction")
    )
end

function GodSystemTerminalUpgrades.snapshotTerminal(terminal, player)
    if not terminal or not terminal.getInventory then return {} end
    local ok, inventory = pcall(function() return terminal:getInventory() end)
    if not ok or not inventory then return {} end
    return {
        terminal = terminal,
        inventory = inventory,
        outerCapacity = readNumberMethod(terminal, "getCapacity"),
        innerCapacity = readNumberMethod(inventory, "getCapacity"),
        outerReduction = readNumberMethod(terminal, "getWeightReduction"),
        innerReduction = readNumberMethod(inventory, "getWeightReduction"),
        relief = GodSystemTerminalRelief.snapshot(terminal, player),
    }
end

function GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.terminal or not snapshot.inventory then return true, nil end
    local ok = true
    local terminalChanged = false
    local function restoreNumber(target, setter, getter, value)
        if not finite(value) then return end
        local writeOk, changed = writeNumberMethod(target, setter, getter, value)
        ok = writeOk and ok
        terminalChanged = changed or terminalChanged
    end
    restoreNumber(snapshot.terminal, "setCapacity", "getCapacity", snapshot.outerCapacity)
    restoreNumber(snapshot.inventory, "setCapacity", "getCapacity", snapshot.innerCapacity)
    restoreNumber(snapshot.terminal, "setWeightReduction", "getWeightReduction", snapshot.outerReduction)
    restoreNumber(snapshot.inventory, "setWeightReduction", "getWeightReduction", snapshot.innerReduction)
    local reliefOk, reliefReport = GodSystemTerminalRelief.restore(snapshot.relief)
    reliefReport = type(reliefReport) == "table" and reliefReport or {}
    reliefReport.inventory = reliefReport.inventory or snapshot.inventory
    reliefReport.terminalChanged = terminalChanged
    return reliefOk and ok, reliefReport
end

function GodSystemTerminalUpgrades.applyTerminal(terminal, data, player)
    if not terminal or not terminal.getInventory then return false, { reason = "missing" } end
    GodSystemTerminalUpgrades.normalizeData(data)
    local okInventory, inventory = pcall(function() return terminal:getInventory() end)
    if not okInventory or not inventory then return false, { reason = "unsupported" } end

    local capacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local reduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    local outerCapacityOk, outerCapacityChanged = writeNumberMethod(terminal, "setCapacity", "getCapacity", capacity)
    local innerCapacityOk, innerCapacityChanged = writeNumberMethod(inventory, "setCapacity", "getCapacity", capacity)
    if not outerCapacityOk or not innerCapacityOk then return false, { reason = "capacityWriteFailed" } end

    local outerReductionOk, outerReductionChanged = writeNumberMethod(terminal, "setWeightReduction", "getWeightReduction", reduction)
    local innerReductionOk, innerReductionChanged = writeNumberMethod(inventory, "setWeightReduction", "getWeightReduction", reduction)
    if not outerReductionOk or not innerReductionOk then return false, { reason = "reductionWriteFailed" } end

    local terminalDataChanged = false
    local terminalData = itemModData(terminal)
    if terminalData then
        terminalDataChanged = writeTableValue(terminalData, GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel", GodSystemTerminalUpgrades.getLevel(data, "capacity")) or terminalDataChanged
        terminalDataChanged = writeTableValue(terminalData, GodSystemConfig.AutoRecyclerReductionLevelKey or "GodSystemTerminalReductionLevel", GodSystemTerminalUpgrades.getLevel(data, "reduction")) or terminalDataChanged
        terminalDataChanged = writeTableValue(terminalData, GodSystemConfig.TerminalReliefLevelKey or "GodSystemTerminalReliefLevel", GodSystemTerminalRelief.getLevel(data)) or terminalDataChanged
    end

    local reliefOk, reliefReport = GodSystemTerminalRelief.ensureTerminal(terminal, data, player)
    if not reliefOk then return false, { reason = "reliefApplyFailed", relief = reliefReport } end

    local report = {
        capacity = capacity,
        reduction = reduction,
        reliefLevel = GodSystemTerminalRelief.getLevel(data),
        reliefOffset = GodSystemTerminalRelief.getOffset(data),
        items = reliefReport.items or {},
        addedItems = reliefReport.addedItems or {},
        removedItems = reliefReport.removedItems or {},
        inventory = reliefReport.inventory or inventory,
        terminalChanged = outerCapacityChanged or innerCapacityChanged
            or outerReductionChanged or innerReductionChanged or terminalDataChanged,
        skipped = 0,
    }
    return true, report
end

function GodSystemTerminalUpgrades.getAppliedStatus(terminal, data, player)
    GodSystemTerminalUpgrades.normalizeData(data)
    local inventory = nil
    if terminal and terminal.getInventory then
        local ok, value = pcall(function() return terminal:getInventory() end)
        if ok then inventory = value end
    end
    local expectedCapacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local expectedReduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    local expectedRelief = GodSystemTerminalRelief.getOffset(data)
    local reliefSnapshot = GodSystemTerminalRelief.snapshot(terminal, player)
    local reliefStates = reliefSnapshot.items or {}
    local actualRelief = #reliefStates == 1 and -(tonumber(reliefStates[1].actualWeight) or 0) or 0
    local outerCapacity = readNumberMethod(terminal, "getCapacity")
    local innerCapacity = readNumberMethod(inventory, "getCapacity")
    local outerReduction = readNumberMethod(terminal, "getWeightReduction")
    local innerReduction = readNumberMethod(inventory, "getWeightReduction")
    return {
        expectedCapacity = expectedCapacity,
        expectedReduction = expectedReduction,
        expectedRelief = expectedRelief,
        outerCapacity = outerCapacity,
        innerCapacity = innerCapacity,
        nativeOuterCapacity = outerCapacity,
        nativeInnerCapacity = innerCapacity,
        outerReduction = outerReduction,
        innerReduction = innerReduction,
        actualRelief = actualRelief,
        reliefItemCount = #reliefStates,
        capacityApplied = outerCapacity ~= nil and innerCapacity ~= nil
            and math.abs(outerCapacity - expectedCapacity) <= EPSILON
            and math.abs(innerCapacity - expectedCapacity) <= EPSILON,
        reductionApplied = outerReduction ~= nil and innerReduction ~= nil
            and math.abs(outerReduction - expectedReduction) <= EPSILON
            and math.abs(innerReduction - expectedReduction) <= EPSILON,
        reliefApplied = expectedRelief <= 0 and #reliefStates == 0
            or (#reliefStates == 1 and math.abs(actualRelief - expectedRelief) <= math.max(0.05, expectedRelief * 0.0001)),
    }
end

return GodSystemTerminalUpgrades
