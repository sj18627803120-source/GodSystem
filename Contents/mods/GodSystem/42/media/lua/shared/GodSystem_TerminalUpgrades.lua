require "GodSystem_Config"
require "GodSystem_TerminalRelief"
require "GodSystem_LegacyCompressionCleanup"

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
    if not target or not target[method] then return nil end
    local ok, value = pcall(function() return target[method](target) end)
    value = ok and tonumber(value) or nil
    return finite(value) and value or nil
end

local function writeNumberMethod(target, setter, getter, value)
    if not target or not target[setter] or not target[getter] then return false, "unsupported" end
    local ok = pcall(function() target[setter](target, value) end)
    if not ok then return false, "writeException" end
    local after = readNumberMethod(target, getter)
    if after == nil or math.abs(after - value) > EPSILON then return false, "verificationFailed" end
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
    return nil
end

local function canRestoreLegacyWeights()
    return not (isClient and isClient()) or (isServer and isServer())
end

function GodSystemTerminalUpgrades.getLevels(upgradeType)
    upgradeType = upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" then return GodSystemConfig.TerminalCapacityLevels or {} end
    if upgradeType == "reduction" then return GodSystemConfig.TerminalReductionLevels or {} end
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
    local legacy = normalizeLevel(data.autoRecyclerLevel, #capacityLevels)
    if data.autoRecyclerCapacityLevel == nil then data.autoRecyclerCapacityLevel = legacy end
    if data.autoRecyclerReductionLevel == nil then data.autoRecyclerReductionLevel = math.min(legacy, #reductionLevels) end
    data.autoRecyclerCapacityLevel = normalizeLevel(data.autoRecyclerCapacityLevel, #capacityLevels)
    data.autoRecyclerReductionLevel = normalizeLevel(data.autoRecyclerReductionLevel, #reductionLevels)
    data.autoRecyclerLevel = data.autoRecyclerCapacityLevel
    GodSystemTerminalRelief.getLevel(data)
    return data
end

function GodSystemTerminalUpgrades.getLevel(data, upgradeType)
    GodSystemTerminalUpgrades.normalizeData(data)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then return GodSystemTerminalRelief.getLevel(data) end
    local field = GodSystemTerminalUpgrades.getField(key)
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    return field and normalizeLevel(data and data[field], #levels) or 1
end

function GodSystemTerminalUpgrades.setLevel(data, upgradeType, level)
    GodSystemTerminalUpgrades.normalizeData(data)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then return GodSystemTerminalRelief.setLevel(data, level) end
    local field = GodSystemTerminalUpgrades.getField(key)
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    if not field or #levels <= 0 then return false end
    data[field] = normalizeLevel(level, #levels)
    if key == "capacity" then data.autoRecyclerLevel = data[field] end
    return true
end

function GodSystemTerminalUpgrades.getLevelData(data, upgradeType, level)
    local key = upgradeTypeKey(upgradeType)
    if key == "relief" then
        local info = GodSystemTerminalRelief.getUpgradeInfo(data)
        return { level = info.level, value = info.offset, upgradeCost = info.nextCost or 0 }
    end
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    level = normalizeLevel(level or GodSystemTerminalUpgrades.getLevel(data, key), #levels)
    return levels[level] or levels[1] or { level = 1, value = 0, upgradeCost = 0 }
end

function GodSystemTerminalUpgrades.getUpgradeInfo(data, upgradeType)
    local key = upgradeTypeKey(upgradeType)
    if not key then return nil end
    if key == "relief" then return GodSystemTerminalRelief.getUpgradeInfo(data) end
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

function GodSystemTerminalUpgrades.snapshotTerminal(terminal)
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
        relief = GodSystemTerminalRelief.snapshot(terminal),
    }
end

function GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.terminal or not snapshot.inventory then return true, nil end
    local ok = true
    if finite(snapshot.outerCapacity) then ok = writeNumberMethod(snapshot.terminal, "setCapacity", "getCapacity", snapshot.outerCapacity) and ok end
    if finite(snapshot.innerCapacity) then ok = writeNumberMethod(snapshot.inventory, "setCapacity", "getCapacity", snapshot.innerCapacity) and ok end
    if finite(snapshot.outerReduction) then ok = writeNumberMethod(snapshot.terminal, "setWeightReduction", "getWeightReduction", snapshot.outerReduction) and ok end
    if finite(snapshot.innerReduction) then ok = writeNumberMethod(snapshot.inventory, "setWeightReduction", "getWeightReduction", snapshot.innerReduction) and ok end
    local reliefOk, reliefReport = GodSystemTerminalRelief.restore(snapshot.relief)
    return reliefOk and ok, reliefReport
end

function GodSystemTerminalUpgrades.applyTerminal(terminal, data)
    if not terminal or not terminal.getInventory then return false, { reason = "missing" } end
    GodSystemTerminalUpgrades.normalizeData(data)
    local okInventory, inventory = pcall(function() return terminal:getInventory() end)
    if not okInventory or not inventory then return false, { reason = "unsupported" } end

    local capacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local reduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    local outerCapacityOk = writeNumberMethod(terminal, "setCapacity", "getCapacity", capacity)
    local innerCapacityOk = writeNumberMethod(inventory, "setCapacity", "getCapacity", capacity)
    if not outerCapacityOk or not innerCapacityOk then return false, { reason = "capacityWriteFailed" } end

    local outerReductionOk = writeNumberMethod(terminal, "setWeightReduction", "getWeightReduction", reduction)
    local innerReductionOk = writeNumberMethod(inventory, "setWeightReduction", "getWeightReduction", reduction)
    if not outerReductionOk or not innerReductionOk then return false, { reason = "reductionWriteFailed" } end

    local terminalData = itemModData(terminal)
    if terminalData then
        terminalData[GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
        terminalData[GodSystemConfig.AutoRecyclerReductionLevelKey or "GodSystemTerminalReductionLevel"] = GodSystemTerminalUpgrades.getLevel(data, "reduction")
        terminalData[GodSystemConfig.AutoRecyclerLevelKey or "GodSystemAutoRecyclerLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
        terminalData[GodSystemConfig.TerminalReliefLevelKey or "GodSystemTerminalReliefLevel"] = GodSystemTerminalRelief.getLevel(data)
    end

    local migrationOk, restoredItems, migrationFailed = true, {}, 0
    if canRestoreLegacyWeights() then
        migrationOk, restoredItems, migrationFailed = GodSystemLegacyCompressionCleanup.restoreTerminal(terminal)
    end
    local reliefOk, reliefReport = GodSystemTerminalRelief.ensureTerminal(terminal, data)
    if not reliefOk then return false, { reason = "reliefApplyFailed", relief = reliefReport } end

    local report = {
        capacity = capacity,
        reduction = reduction,
        reliefLevel = GodSystemTerminalRelief.getLevel(data),
        reliefOffset = GodSystemTerminalRelief.getOffset(data),
        migrationOk = migrationOk,
        migrationRestored = #(restoredItems or {}),
        migrationFailed = migrationFailed or 0,
        items = reliefReport.items or {},
        addedItems = reliefReport.addedItems or {},
        removedItems = reliefReport.removedItems or {},
        inventory = reliefReport.inventory or inventory,
        restoredItems = restoredItems or {},
        skipped = 0,
    }
    return true, report
end

function GodSystemTerminalUpgrades.getAppliedStatus(terminal, data)
    GodSystemTerminalUpgrades.normalizeData(data)
    local inventory = nil
    if terminal and terminal.getInventory then
        local ok, value = pcall(function() return terminal:getInventory() end)
        if ok then inventory = value end
    end
    local expectedCapacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local expectedReduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    local expectedRelief = GodSystemTerminalRelief.getOffset(data)
    local reliefSnapshot = GodSystemTerminalRelief.snapshot(terminal)
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

function GodSystemTerminalUpgrades.restoreTerminal(terminal)
    if not terminal then return true, {} end
    if canRestoreLegacyWeights() then
        local ok, restoredItems = GodSystemLegacyCompressionCleanup.restoreTerminal(terminal)
        return ok, restoredItems or {}
    end
    return true, {}
end

return GodSystemTerminalUpgrades
