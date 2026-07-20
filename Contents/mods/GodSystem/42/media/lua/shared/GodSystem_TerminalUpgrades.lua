require "GodSystem_Config"
require "GodSystem_TerminalCapacity"
require "GodSystem_LegacyCompressionCleanup"

GodSystemTerminalUpgrades = GodSystemTerminalUpgrades or {}

local EPSILON = 0.0001
local NATIVE_SAFE_CAPACITY = 49

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
    return data
end

function GodSystemTerminalUpgrades.getLevel(data, upgradeType)
    GodSystemTerminalUpgrades.normalizeData(data)
    local field = GodSystemTerminalUpgrades.getField(upgradeType)
    local levels = GodSystemTerminalUpgrades.getLevels(upgradeType)
    return field and normalizeLevel(data and data[field], #levels) or 1
end

function GodSystemTerminalUpgrades.setLevel(data, upgradeType, level)
    GodSystemTerminalUpgrades.normalizeData(data)
    local key = upgradeTypeKey(upgradeType)
    local field = GodSystemTerminalUpgrades.getField(key)
    local levels = GodSystemTerminalUpgrades.getLevels(key)
    if not field or #levels <= 0 then return false end
    data[field] = normalizeLevel(level, #levels)
    if key == "capacity" then data.autoRecyclerLevel = data[field] end
    return true
end

function GodSystemTerminalUpgrades.getLevelData(data, upgradeType, level)
    local levels = GodSystemTerminalUpgrades.getLevels(upgradeType)
    level = normalizeLevel(level or GodSystemTerminalUpgrades.getLevel(data, upgradeType), #levels)
    return levels[level] or levels[1] or { level = 1, value = 0, upgradeCost = 0 }
end

function GodSystemTerminalUpgrades.getUpgradeInfo(data, upgradeType)
    local key = upgradeTypeKey(upgradeType)
    if not key then return nil end
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
    local data = itemModData(terminal) or {}
    return {
        terminal = terminal,
        inventory = inventory,
        outerCapacity = readNumberMethod(terminal, "getCapacity"),
        innerCapacity = readNumberMethod(inventory, "getCapacity"),
        outerReduction = readNumberMethod(terminal, "getWeightReduction"),
        innerReduction = readNumberMethod(inventory, "getWeightReduction"),
        targetCapacity = data[GodSystemConfig.AutoRecyclerTargetCapacityKey or "GodSystemTerminalTargetCapacity"],
    }
end

function GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
    if type(snapshot) ~= "table" or not snapshot.terminal or not snapshot.inventory then return true end
    local ok = true
    if finite(snapshot.outerCapacity) then ok = writeNumberMethod(snapshot.terminal, "setCapacity", "getCapacity", snapshot.outerCapacity) and ok end
    if finite(snapshot.innerCapacity) then ok = writeNumberMethod(snapshot.inventory, "setCapacity", "getCapacity", snapshot.innerCapacity) and ok end
    if finite(snapshot.outerReduction) then ok = writeNumberMethod(snapshot.terminal, "setWeightReduction", "getWeightReduction", snapshot.outerReduction) and ok end
    if finite(snapshot.innerReduction) then ok = writeNumberMethod(snapshot.inventory, "setWeightReduction", "getWeightReduction", snapshot.innerReduction) and ok end
    if finite(snapshot.targetCapacity) then
        ok = GodSystemTerminalCapacity.register(snapshot.terminal, snapshot.targetCapacity) and ok
    end
    return ok
end

function GodSystemTerminalUpgrades.applyTerminal(terminal, data)
    if not terminal or not terminal.getInventory then return false, { reason = "missing" } end
    GodSystemTerminalUpgrades.normalizeData(data)
    local okInventory, inventory = pcall(function() return terminal:getInventory() end)
    if not okInventory or not inventory then return false, { reason = "unsupported" } end

    local capacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local reduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    if capacity > NATIVE_SAFE_CAPACITY and not GodSystemTerminalCapacity.install() then
        return false, { reason = "capacityOverrideUnavailable" }
    end
    local nativeCapacity = math.min(capacity, NATIVE_SAFE_CAPACITY)
    local outerCapacityOk = writeNumberMethod(terminal, "setCapacity", "getCapacity", nativeCapacity)
    local innerCapacityOk = writeNumberMethod(inventory, "setCapacity", "getCapacity", nativeCapacity)
    if not outerCapacityOk or not innerCapacityOk then return false, { reason = "capacityWriteFailed" } end

    local outerReductionOk = writeNumberMethod(terminal, "setWeightReduction", "getWeightReduction", reduction)
    local innerReductionOk = writeNumberMethod(inventory, "setWeightReduction", "getWeightReduction", reduction)
    if not outerReductionOk or not innerReductionOk then return false, { reason = "reductionWriteFailed" } end
    if not GodSystemTerminalCapacity.register(terminal, capacity) then return false, { reason = "capacityRegisterFailed" } end

    local terminalData = itemModData(terminal)
    if terminalData then
        terminalData[GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
        terminalData[GodSystemConfig.AutoRecyclerReductionLevelKey or "GodSystemTerminalReductionLevel"] = GodSystemTerminalUpgrades.getLevel(data, "reduction")
        terminalData[GodSystemConfig.AutoRecyclerLevelKey or "GodSystemAutoRecyclerLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
    end

    local migrationOk, restoredItems, migrationFailed = true, {}, 0
    if canRestoreLegacyWeights() then
        migrationOk, restoredItems, migrationFailed = GodSystemLegacyCompressionCleanup.restoreTerminal(terminal)
    end
    local report = {
        capacity = capacity,
        reduction = reduction,
        nativeCapacity = nativeCapacity,
        migrationOk = migrationOk,
        migrationRestored = #(restoredItems or {}),
        migrationFailed = migrationFailed or 0,
        items = {},
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
    local registeredCapacity = inventory and GodSystemTerminalCapacity.getRegisteredCapacity(inventory) or nil
    local outerReduction = readNumberMethod(terminal, "getWeightReduction")
    local innerReduction = readNumberMethod(inventory, "getWeightReduction")
    return {
        expectedCapacity = expectedCapacity,
        expectedReduction = expectedReduction,
        outerCapacity = registeredCapacity,
        innerCapacity = registeredCapacity,
        nativeOuterCapacity = readNumberMethod(terminal, "getCapacity"),
        nativeInnerCapacity = readNumberMethod(inventory, "getCapacity"),
        outerReduction = outerReduction,
        innerReduction = innerReduction,
        capacityApplied = registeredCapacity ~= nil and math.abs(registeredCapacity - expectedCapacity) <= EPSILON,
        reductionApplied = outerReduction ~= nil and innerReduction ~= nil
            and math.abs(outerReduction - expectedReduction) <= EPSILON
            and math.abs(innerReduction - expectedReduction) <= EPSILON,
    }
end

function GodSystemTerminalUpgrades.restoreTerminal(terminal)
    if not terminal then return true, {} end
    local ok, restoredItems = true, {}
    if canRestoreLegacyWeights() then
        ok, restoredItems = GodSystemLegacyCompressionCleanup.restoreTerminal(terminal)
    end
    GodSystemTerminalCapacity.unregister(terminal)
    return ok, restoredItems or {}
end

return GodSystemTerminalUpgrades
