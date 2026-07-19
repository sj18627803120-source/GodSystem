require "GodSystem_Config"

GodSystemTerminalUpgrades = GodSystemTerminalUpgrades or {}
GodSystemTerminalUpgrades.runtime = GodSystemTerminalUpgrades.runtime or {}

local BASE_WEIGHT_KEY = "GodSystemCompressionBaseActualWeight"
local BASE_INPUT_KEY = "GodSystemCompressionBaseInputWeight"
local BASE_CUSTOM_KEY = "GodSystemCompressionBaseCustomWeight"
local LAST_WEIGHT_KEY = "GodSystemCompressionLastAppliedWeight"
local LAST_INPUT_KEY = "GodSystemCompressionLastInputWeight"
local OWNER_KEY = "GodSystemCompressionTerminalId"
local VERSION_KEY = "GodSystemCompressionVersion"
local COMPRESSION_VERSION = 2
local MIN_WEIGHT = 0.01
local EPSILON = 0.0001
local MAX_DEPTH = 32
local BATCH_SIZE = 32
local MAX_DIAGNOSTIC_ROWS = 5

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

local function readDefinitionWeight(item)
    if not item or not item.getScriptItem then return nil end
    local okDefinition, definition = pcall(function() return item:getScriptItem() end)
    if not okDefinition or not definition or not definition.getActualWeight then return nil end
    local okWeight, value = pcall(function() return definition:getActualWeight() end)
    value = okWeight and tonumber(value) or nil
    return finite(value) and value >= 0 and value or nil
end

local function readInputWeight(item)
    if item and item.getWeight then
        local ok, value = pcall(function() return item:getWeight() end)
        value = ok and tonumber(value) or nil
        if finite(value) and value >= 0 then return value end
    end
    return readDefinitionWeight(item)
end

local function writeWeight(item, inputWeight, custom, expectedWeight)
    inputWeight = tonumber(inputWeight)
    expectedWeight = finite(expectedWeight) and tonumber(expectedWeight) or inputWeight
    if not item or not item.setActualWeight or not item.setCustomWeight
        or not finite(inputWeight) or inputWeight < 0 or not finite(expectedWeight) or expectedWeight < 0 then
        return false, "unsupported"
    end
    local expectedCustom = custom == true
    local appliedInput = inputWeight
    local appliedWeight = nil
    local ok = pcall(function()
        -- B42 may refresh ActualWeight when the custom flag changes.  Enter the
        -- custom-weight state first.  HandWeapon overrides getActualWeight(),
        -- so its setter input and effective readback are not always identical.
        item:setCustomWeight(true)
        for _ = 1, 3 do
            item:setActualWeight(appliedInput)
            appliedWeight = readActualWeight(item)
            local tolerance = math.max(EPSILON, math.abs(expectedWeight) * 0.001)
            if appliedWeight ~= nil and math.abs(appliedWeight - expectedWeight) <= tolerance then break end
            if appliedWeight == nil then break end
            appliedInput = appliedInput + (expectedWeight - appliedWeight)
            if not finite(appliedInput) or appliedInput < MIN_WEIGHT then break end
        end
        if not expectedCustom then item:setCustomWeight(false) end
    end)
    if not ok then
        pcall(function() item:setCustomWeight(expectedCustom) end)
        return false, "writeException"
    end
    local after = readActualWeight(item)
    local tolerance = math.max(EPSILON, math.abs(expectedWeight) * 0.001)
    if after == nil or math.abs(after - expectedWeight) > tolerance then
        return false, "actualWeightMismatch", appliedInput, after
    end
    if readCustomWeight(item) ~= expectedCustom then return false, "customFlagMismatch" end
    return true, nil, appliedInput, after
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

local function itemDiagnostic(item, reason)
    local id = ""
    local fullType = ""
    if item and item.getID then
        local ok, value = pcall(function() return item:getID() end)
        if ok then id = tostring(value or "") end
    end
    if item and item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok then fullType = tostring(value or "") end
    end
    return { id = id, fullType = fullType, reason = tostring(reason or "unknown") }
end

local function recordDiagnostic(report, item, reason)
    reason = tostring(reason or "unknown")
    report.reasonCounts[reason] = (report.reasonCounts[reason] or 0) + 1
    if #report.diagnostics < MAX_DIAGNOSTIC_ROWS then
        report.diagnostics[#report.diagnostics + 1] = itemDiagnostic(item, reason)
    end
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
    local baseInput = finite(data[BASE_INPUT_KEY]) and tonumber(data[BASE_INPUT_KEY]) or readInputWeight(item) or baseWeight
    local baseCustom = data[BASE_CUSTOM_KEY] == true
    local ok = writeWeight(item, baseInput, baseCustom, baseWeight)
    if ok then
        data[BASE_WEIGHT_KEY] = nil
        data[BASE_INPUT_KEY] = nil
        data[BASE_CUSTOM_KEY] = nil
        data[LAST_WEIGHT_KEY] = nil
        data[LAST_INPUT_KEY] = nil
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

    local savedBaseWeight = data[BASE_WEIGHT_KEY]
    local savedBaseInput = data[BASE_INPUT_KEY]
    local savedBaseCustom = data[BASE_CUSTOM_KEY]
    local savedLastWeight = data[LAST_WEIGHT_KEY]
    local savedLastInput = data[LAST_INPUT_KEY]
    local savedOwner = data[OWNER_KEY]
    local savedVersion = data[VERSION_KEY]
    local baseWeight = tonumber(data[BASE_WEIGHT_KEY])
    if not finite(baseWeight) then
        if readCustomWeight(item) then return false, "customWeight" end
        baseWeight = current
        data[BASE_WEIGHT_KEY] = baseWeight
        data[BASE_CUSTOM_KEY] = readCustomWeight(item)
    end
    local baseInput = tonumber(data[BASE_INPUT_KEY])
    if not finite(baseInput) then
        baseInput = readInputWeight(item) or baseWeight
        data[BASE_INPUT_KEY] = baseInput
    end
    if baseWeight <= 0 then return true, "zeroWeight" end

    local target = math.max(MIN_WEIGHT, baseWeight * (1 - compression / 100))
    local derivedWeight = baseWeight - baseInput
    local targetInput = target - derivedWeight
    if not finite(targetInput) or targetInput < MIN_WEIGHT then
        data[BASE_WEIGHT_KEY] = savedBaseWeight
        data[BASE_INPUT_KEY] = savedBaseInput
        data[BASE_CUSTOM_KEY] = savedBaseCustom
        data[LAST_WEIGHT_KEY] = savedLastWeight
        data[LAST_INPUT_KEY] = savedLastInput
        data[OWNER_KEY] = savedOwner
        data[VERSION_KEY] = savedVersion
        return false, "derivedWeightFloor"
    end
    local previousWeight = current
    local previousInput = finite(data[LAST_INPUT_KEY]) and tonumber(data[LAST_INPUT_KEY]) or baseInput
    local previousCustom = readCustomWeight(item)
    local written, writeReason, appliedInput, appliedWeight = writeWeight(item, targetInput, true, target)
    if not written then
        local restored = writeWeight(item, previousInput, previousCustom, previousWeight)
        if restored then
            data[BASE_WEIGHT_KEY] = savedBaseWeight
            data[BASE_INPUT_KEY] = savedBaseInput
            data[BASE_CUSTOM_KEY] = savedBaseCustom
            data[LAST_WEIGHT_KEY] = savedLastWeight
            data[LAST_INPUT_KEY] = savedLastInput
            data[OWNER_KEY] = savedOwner
            data[VERSION_KEY] = savedVersion
        else
            -- Keep ownership metadata when rollback itself fails so later
            -- terminal removal/cleanup can continue attempting restoration.
            data[BASE_WEIGHT_KEY] = finite(savedBaseWeight) and savedBaseWeight or previousWeight
            data[BASE_INPUT_KEY] = finite(savedBaseInput) and savedBaseInput or previousInput
            data[BASE_CUSTOM_KEY] = savedBaseCustom ~= nil and savedBaseCustom or previousCustom
            data[LAST_WEIGHT_KEY] = readActualWeight(item) or previousWeight
            data[LAST_INPUT_KEY] = previousInput
            data[OWNER_KEY] = tostring(terminalId or "")
            data[VERSION_KEY] = COMPRESSION_VERSION
        end
        return false, restored and (writeReason or "writeFailed") or ((writeReason or "writeFailed") .. "RestoreFailed")
    end
    data[LAST_WEIGHT_KEY] = appliedWeight or target
    data[LAST_INPUT_KEY] = appliedInput or targetInput
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
            inputWeight = finite(data[LAST_INPUT_KEY]) and tonumber(data[LAST_INPUT_KEY])
                or finite(data[BASE_INPUT_KEY]) and tonumber(data[BASE_INPUT_KEY])
                or readInputWeight(item),
            customWeight = readCustomWeight(item),
            baseWeight = data[BASE_WEIGHT_KEY],
            baseInput = data[BASE_INPUT_KEY],
            baseCustom = data[BASE_CUSTOM_KEY],
            lastWeight = data[LAST_WEIGHT_KEY],
            lastInput = data[LAST_INPUT_KEY],
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
        local ok = row.actualWeight ~= nil and writeWeight(
            row.item,
            finite(row.inputWeight) and row.inputWeight or row.actualWeight,
            row.customWeight,
            row.actualWeight
        )
        if data then
            data[BASE_WEIGHT_KEY] = row.baseWeight
            data[BASE_INPUT_KEY] = row.baseInput
            data[BASE_CUSTOM_KEY] = row.baseCustom
            data[LAST_WEIGHT_KEY] = row.lastWeight
            data[LAST_INPUT_KEY] = row.lastInput
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
    -- InventoryContainer owns the equipped-bag values used by carry-weight
    -- calculations while its child ItemContainer owns the actual contents.
    -- Keep both layers aligned; changing only the child leaves the item-level
    -- reduction at the script default (50 for the system terminal).
    local outerCapacityOk, outerCapacityReason = writeNumberMethod(terminal, "setCapacity", "getCapacity", capacity)
    local innerCapacityOk, innerCapacityReason = writeNumberMethod(inventory, "setCapacity", "getCapacity", capacity)
    if not outerCapacityOk or not innerCapacityOk then
        return false, {
            reason = "capacityWriteFailed",
            outerReason = outerCapacityReason,
            innerReason = innerCapacityReason,
        }
    end
    local outerReductionOk, outerReductionReason = writeNumberMethod(terminal, "setWeightReduction", "getWeightReduction", reduction)
    local innerReductionOk, innerReductionReason = writeNumberMethod(inventory, "setWeightReduction", "getWeightReduction", reduction)
    if not outerReductionOk or not innerReductionOk then
        return false, {
            reason = "reductionWriteFailed",
            outerReason = outerReductionReason,
            innerReason = innerReductionReason,
        }
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
    local report = {
        capacity = capacity,
        reduction = reduction,
        compression = compression,
        processed = 0,
        skipped = 0,
        failed = 0,
        itemCount = 0,
        items = {},
        restoredItems = restoredItems,
        reasonCounts = {},
        diagnostics = {},
    }
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
                recordDiagnostic(report, item, reason)
            else
                -- A single unusual item must not invalidate a paid terminal
                -- level.  The failed instance is restored by compressItem and
                -- reported as skipped; container/API failures above remain
                -- transaction-fatal.
                skipped = skipped + 1
                failed = failed + 1
                recordDiagnostic(report, item, reason)
            end
        end
    end
    for item in pairs(previous.tracked or {}) do
        if not current[item] then
            local itemData = itemModData(item)
            if itemData and tostring(itemData[OWNER_KEY] or "") == terminalId then
                if GodSystemTerminalUpgrades.restoreItem(item) then
                    restoredItems[#restoredItems + 1] = item
                else
                    failed = failed + 1
                    recordDiagnostic(report, item, "restoreFailed")
                end
            end
        end
    end
    previous.terminal = terminal
    previous.tracked = current
    previous.lastCompression = compression
    report.processed = processed
    report.skipped = skipped
    report.failed = failed
    report.itemCount = #rows
    report.items = rows
    previous.lastReport = report
    GodSystemTerminalUpgrades.runtime[terminalId] = previous
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
    local expectedCompression = GodSystemTerminalUpgrades.getLevelData(data, "compression").value or 0
    local outerCapacity = readNumberMethod(terminal, "getCapacity")
    local innerCapacity = readNumberMethod(inventory, "getCapacity")
    local outerReduction = readNumberMethod(terminal, "getWeightReduction")
    local innerReduction = readNumberMethod(inventory, "getWeightReduction")
    local runtime = terminal and GodSystemTerminalUpgrades.runtime[GodSystemTerminalUpgrades.getTerminalId(terminal)] or nil
    local lastReport = runtime and runtime.lastReport or nil
    return {
        expectedCapacity = expectedCapacity,
        expectedReduction = expectedReduction,
        expectedCompression = expectedCompression,
        outerCapacity = outerCapacity,
        innerCapacity = innerCapacity,
        outerReduction = outerReduction,
        innerReduction = innerReduction,
        capacityApplied = outerCapacity ~= nil and innerCapacity ~= nil
            and math.abs(outerCapacity - expectedCapacity) <= EPSILON
            and math.abs(innerCapacity - expectedCapacity) <= EPSILON,
        reductionApplied = outerReduction ~= nil and innerReduction ~= nil
            and math.abs(outerReduction - expectedReduction) <= EPSILON
            and math.abs(innerReduction - expectedReduction) <= EPSILON,
        processed = lastReport and lastReport.processed or 0,
        skipped = lastReport and lastReport.skipped or 0,
        failed = lastReport and lastReport.failed or 0,
        diagnostics = lastReport and lastReport.diagnostics or {},
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
