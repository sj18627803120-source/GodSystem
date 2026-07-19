require "GodSystem_Config"

GodSystemTerminalUpgrades = GodSystemTerminalUpgrades or {}
GodSystemTerminalUpgrades.runtime = GodSystemTerminalUpgrades.runtime or {}

local BASE_WEIGHT_KEY = "GodSystemCompressionBaseActualWeight"
local BASE_CUSTOM_KEY = "GodSystemCompressionBaseCustomWeight"
local LAST_WEIGHT_KEY = "GodSystemCompressionLastAppliedWeight"
local OWNER_KEY = "GodSystemCompressionTerminalId"
local VERSION_KEY = "GodSystemCompressionVersion"
local COMPRESSION_VERSION = 1
local MIN_WEIGHT = 0.01
local EPSILON = 0.0001
local MAX_DEPTH = 32
local BATCH_SIZE = 32

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function itemModData(item)
    if not item or not item.getModData then return nil end
    local ok, data = pcall(function() return item:getModData() end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function readActualWeight(item)
    if not item or not item.getActualWeight then return nil end
    local ok, value = pcall(function() return item:getActualWeight() end)
    value = ok and tonumber(value) or nil
    if not finite(value) or value < 0 then return nil end
    return value
end

local function readCustomWeight(item)
    if not item or not item.isCustomWeight then return false end
    local ok, value = pcall(function() return item:isCustomWeight() end)
    return ok and value == true
end

local function writeWeight(item, weight, custom)
    if not item or not item.setActualWeight or not item.setCustomWeight or not finite(weight) or weight < 0 then return false end
    local ok = pcall(function()
        item:setActualWeight(weight)
        item:setCustomWeight(custom == true)
    end)
    if not ok then return false end
    local after = readActualWeight(item)
    return after ~= nil and math.abs(after - weight) <= EPSILON
end

local function normalizeLevel(value, maximum)
    value = math.floor(tonumber(value) or 1)
    return math.max(1, math.min(value, math.max(1, maximum or 1)))
end

local function upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" or upgradeType == "terminalCapacity" then return "capacity" end
    if upgradeType == "reduction" or upgradeType == "terminalReduction" then return "reduction" end
    if upgradeType == "compression" or upgradeType == "terminalCompression" then return "compression" end
    return nil
end

function GodSystemTerminalUpgrades.getLevels(upgradeType)
    upgradeType = upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" then return GodSystemConfig.TerminalCapacityLevels or {} end
    if upgradeType == "reduction" then return GodSystemConfig.TerminalReductionLevels or {} end
    if upgradeType == "compression" then return GodSystemConfig.TerminalCompressionLevels or {} end
    return {}
end

function GodSystemTerminalUpgrades.getField(upgradeType)
    upgradeType = upgradeTypeKey(upgradeType)
    if upgradeType == "capacity" then return "autoRecyclerCapacityLevel" end
    if upgradeType == "reduction" then return "autoRecyclerReductionLevel" end
    if upgradeType == "compression" then return "autoRecyclerCompressionLevel" end
    return nil
end

function GodSystemTerminalUpgrades.normalizeData(data)
    if type(data) ~= "table" then return data end
    local legacy = normalizeLevel(data.autoRecyclerLevel, #(GodSystemConfig.AutoRecyclerLevels or {}))
    if data.autoRecyclerCapacityLevel == nil then data.autoRecyclerCapacityLevel = legacy end
    if data.autoRecyclerReductionLevel == nil then data.autoRecyclerReductionLevel = legacy end
    if data.autoRecyclerCompressionLevel == nil then data.autoRecyclerCompressionLevel = 1 end
    data.autoRecyclerCapacityLevel = normalizeLevel(data.autoRecyclerCapacityLevel, #GodSystemTerminalUpgrades.getLevels("capacity"))
    data.autoRecyclerReductionLevel = normalizeLevel(data.autoRecyclerReductionLevel, #GodSystemTerminalUpgrades.getLevels("reduction"))
    data.autoRecyclerCompressionLevel = normalizeLevel(data.autoRecyclerCompressionLevel, #GodSystemTerminalUpgrades.getLevels("compression"))
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
    local field = GodSystemTerminalUpgrades.getField(upgradeType)
    local levels = GodSystemTerminalUpgrades.getLevels(upgradeType)
    if not field or #levels <= 0 then return false end
    data[field] = normalizeLevel(level, #levels)
    if upgradeTypeKey(upgradeType) == "capacity" then data.autoRecyclerLevel = data[field] end
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
        GodSystemTerminalUpgrades.getLevel(data, "reduction"),
        GodSystemTerminalUpgrades.getLevel(data, "compression")
    )
end

function GodSystemTerminalUpgrades.getTerminalId(item)
    if not item or not item.getID then return tostring(item or "") end
    local ok, value = pcall(function() return item:getID() end)
    return ok and tostring(value or "") or tostring(item)
end

function GodSystemTerminalUpgrades.restoreItem(item)
    local data = itemModData(item)
    if not data or not finite(data[BASE_WEIGHT_KEY]) then return false end
    local baseWeight = tonumber(data[BASE_WEIGHT_KEY])
    local baseCustom = data[BASE_CUSTOM_KEY] == true
    local ok = writeWeight(item, baseWeight, baseCustom)
    if ok then
        data[BASE_WEIGHT_KEY] = nil
        data[BASE_CUSTOM_KEY] = nil
        data[LAST_WEIGHT_KEY] = nil
        data[OWNER_KEY] = nil
        data[VERSION_KEY] = nil
    end
    return ok
end

function GodSystemTerminalUpgrades.compressItem(item, compression, terminalId)
    compression = math.max(0, math.min(99, tonumber(compression) or 0))
    local data = itemModData(item)
    local current = readActualWeight(item)
    if not data or current == nil then return false, "unsupported" end
    if compression <= 0 then
        if finite(data[BASE_WEIGHT_KEY]) then return GodSystemTerminalUpgrades.restoreItem(item), "restored" end
        return true, "unchanged"
    end

    local baseWeight = tonumber(data[BASE_WEIGHT_KEY])
    if not finite(baseWeight) then
        if readCustomWeight(item) then return false, "customWeight" end
        baseWeight = current
        data[BASE_WEIGHT_KEY] = baseWeight
        data[BASE_CUSTOM_KEY] = readCustomWeight(item)
    end
    if baseWeight <= 0 then return true, "zeroWeight" end

    local target = math.max(MIN_WEIGHT, baseWeight * (1 - compression / 100))
    local previousWeight = current
    local previousCustom = readCustomWeight(item)
    if not writeWeight(item, target, true) then
        writeWeight(item, previousWeight, previousCustom)
        return false, "writeFailed"
    end
    data[LAST_WEIGHT_KEY] = target
    data[OWNER_KEY] = tostring(terminalId or "")
    data[VERSION_KEY] = COMPRESSION_VERSION
    return true, "compressed"
end

local function collectInventory(inventory, rows, seen, depth)
    if not inventory or not inventory.getItems or depth > MAX_DEPTH then return end
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items or not items.size then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and not seen[item] then
            seen[item] = true
            rows[#rows + 1] = item
            if item.getInventory then
                local childOk, child = pcall(function() return item:getInventory() end)
                if childOk and child then collectInventory(child, rows, seen, depth + 1) end
            end
        end
    end
end

function GodSystemTerminalUpgrades.collectTerminalItems(terminal)
    local rows = {}
    if terminal and terminal.getInventory then
        local ok, inventory = pcall(function() return terminal:getInventory() end)
        if ok and inventory then collectInventory(inventory, rows, {}, 0) end
    end
    return rows
end

function GodSystemTerminalUpgrades.snapshotTerminal(terminal)
    local snapshot = {}
    local rows = GodSystemTerminalUpgrades.collectTerminalItems(terminal)
    for i = 1, #rows do
        local item = rows[i]
        local data = itemModData(item) or {}
        snapshot[#snapshot + 1] = {
            item = item,
            actualWeight = readActualWeight(item),
            customWeight = readCustomWeight(item),
            baseWeight = data[BASE_WEIGHT_KEY],
            baseCustom = data[BASE_CUSTOM_KEY],
            lastWeight = data[LAST_WEIGHT_KEY],
            owner = data[OWNER_KEY],
            version = data[VERSION_KEY],
        }
    end
    return snapshot
end

function GodSystemTerminalUpgrades.restoreSnapshot(snapshot)
    local okAll = true
    for i = 1, #(snapshot or {}) do
        local row = snapshot[i]
        local data = itemModData(row.item)
        local ok = row.actualWeight ~= nil and writeWeight(row.item, row.actualWeight, row.customWeight)
        if data then
            data[BASE_WEIGHT_KEY] = row.baseWeight
            data[BASE_CUSTOM_KEY] = row.baseCustom
            data[LAST_WEIGHT_KEY] = row.lastWeight
            data[OWNER_KEY] = row.owner
            data[VERSION_KEY] = row.version
        end
        okAll = okAll and ok == true
    end
    return okAll
end

function GodSystemTerminalUpgrades.applyTerminal(terminal, data)
    if not terminal or not terminal.getInventory then return false, { reason = "missing" } end
    GodSystemTerminalUpgrades.normalizeData(data)
    local okInventory, inventory = pcall(function() return terminal:getInventory() end)
    if not okInventory or not inventory then return false, { reason = "unsupported" } end

    local capacity = GodSystemTerminalUpgrades.getLevelData(data, "capacity").value or 10
    local reduction = GodSystemTerminalUpgrades.getLevelData(data, "reduction").value or 50
    local compression = GodSystemTerminalUpgrades.getLevelData(data, "compression").value or 0
    if not inventory.setCapacity or not inventory.setWeightReduction then return false, { reason = "containerApiUnavailable" } end
    local capacityOk = pcall(function() inventory:setCapacity(capacity) end)
    local reductionOk = pcall(function() inventory:setWeightReduction(reduction) end)
    if not capacityOk or not reductionOk then return false, { reason = "containerWriteFailed" } end
    if inventory.getCapacity then
        local ok, appliedCapacity = pcall(function() return inventory:getCapacity() end)
        if not ok or math.abs((tonumber(appliedCapacity) or -1) - capacity) > EPSILON then return false, { reason = "capacityVerificationFailed" } end
    end
    if inventory.getWeightReduction then
        local ok, appliedReduction = pcall(function() return inventory:getWeightReduction() end)
        if not ok or math.abs((tonumber(appliedReduction) or -1) - reduction) > EPSILON then return false, { reason = "reductionVerificationFailed" } end
    end

    local terminalData = itemModData(terminal)
    if terminalData then
        terminalData[GodSystemConfig.AutoRecyclerCapacityLevelKey or "GodSystemTerminalCapacityLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
        terminalData[GodSystemConfig.AutoRecyclerReductionLevelKey or "GodSystemTerminalReductionLevel"] = GodSystemTerminalUpgrades.getLevel(data, "reduction")
        terminalData[GodSystemConfig.AutoRecyclerCompressionLevelKey or "GodSystemTerminalCompressionLevel"] = GodSystemTerminalUpgrades.getLevel(data, "compression")
        terminalData[GodSystemConfig.AutoRecyclerLevelKey or "GodSystemAutoRecyclerLevel"] = GodSystemTerminalUpgrades.getLevel(data, "capacity")
    end

    local terminalId = GodSystemTerminalUpgrades.getTerminalId(terminal)
    local previous = GodSystemTerminalUpgrades.runtime[terminalId] or { tracked = {} }
    local current = {}
    local processed = 0
    local skipped = 0
    local failed = 0
    local restoredItems = {}
    local rows = GodSystemTerminalUpgrades.collectTerminalItems(terminal)
    for batchStart = 1, #rows, BATCH_SIZE do
        local batchEnd = math.min(#rows, batchStart + BATCH_SIZE - 1)
        for i = batchStart, batchEnd do
            local item = rows[i]
            current[item] = true
            local ok, reason = GodSystemTerminalUpgrades.compressItem(item, compression, terminalId)
            if ok then
                processed = processed + 1
            elseif reason == "customWeight" then
                skipped = skipped + 1
            else
                failed = failed + 1
            end
        end
    end
    for item in pairs(previous.tracked or {}) do
        if not current[item] then
            local itemData = itemModData(item)
            if itemData and tostring(itemData[OWNER_KEY] or "") == terminalId and GodSystemTerminalUpgrades.restoreItem(item) then
                restoredItems[#restoredItems + 1] = item
            end
        end
    end
    previous.terminal = terminal
    previous.tracked = current
    previous.lastCompression = compression
    GodSystemTerminalUpgrades.runtime[terminalId] = previous
    return failed == 0, {
        capacity = capacity,
        reduction = reduction,
        compression = compression,
        processed = processed,
        skipped = skipped,
        failed = failed,
        itemCount = #rows,
        items = rows,
        restoredItems = restoredItems,
    }
end

function GodSystemTerminalUpgrades.restoreTerminal(terminal)
    if not terminal then return true, {} end
    local terminalId = GodSystemTerminalUpgrades.getTerminalId(terminal)
    local rows = GodSystemTerminalUpgrades.collectTerminalItems(terminal)
    local okAll = true
    local restoredItems = {}
    for i = 1, #rows do
        local data = itemModData(rows[i])
        if data and tostring(data[OWNER_KEY] or "") == terminalId then
            local restored = GodSystemTerminalUpgrades.restoreItem(rows[i])
            if restored then restoredItems[#restoredItems + 1] = rows[i] end
            okAll = restored and okAll
        end
    end
    local runtime = GodSystemTerminalUpgrades.runtime[terminalId]
    for item in pairs(runtime and runtime.tracked or {}) do
        local data = itemModData(item)
        if data and finite(data[BASE_WEIGHT_KEY]) and tostring(data[OWNER_KEY] or "") == terminalId then
            local restored = GodSystemTerminalUpgrades.restoreItem(item)
            if restored then restoredItems[#restoredItems + 1] = item end
            okAll = restored and okAll
        end
    end
    GodSystemTerminalUpgrades.runtime[terminalId] = nil
    return okAll, restoredItems
end

function GodSystemTerminalUpgrades.isCompressedByTerminal(item, terminal)
    local data = itemModData(item)
    if not data or not finite(data[BASE_WEIGHT_KEY]) then return false end
    return tostring(data[OWNER_KEY] or "") == GodSystemTerminalUpgrades.getTerminalId(terminal)
end

return GodSystemTerminalUpgrades
