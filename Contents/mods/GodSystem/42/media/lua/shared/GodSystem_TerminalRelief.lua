require "GodSystem_Config"
require "GodSystem_AdminConfig"
require "GodSystem_B42JavaCalls"

GodSystemTerminalRelief = GodSystemTerminalRelief or {}

local DATA_FIELD = "autoRecyclerReliefLevel"
local PHASE2_DATA_FIELD = "autoRecyclerPhase2CapacityLevel"
local AUDIT_VERSION = 2
local EPSILON = 0.05

local function setting(key, fallback)
    if GodSystemAdminConfig and GodSystemAdminConfig.getSetting then
        local value = GodSystemAdminConfig.getSetting(key, fallback)
        if value ~= nil then return value end
    end
    return fallback
end

local function integerSetting(key, fallback, minimum)
    local value = math.floor(tonumber(setting(key, fallback)) or fallback)
    return math.max(minimum or 0, value)
end

local function phase2Step()
    return math.max(1, math.floor(tonumber(GodSystemConfig.TerminalPhase2CapacityPerLevel) or 10))
end

local function phase2Maximum()
    local configured = integerSetting("TerminalPhase2CapacityMaxOffset", GodSystemConfig.TerminalPhase2CapacityMaxOffset or 5000, 0)
    configured = math.min(5000, configured)
    return math.floor(configured / phase2Step()) * phase2Step()
end

local function reliefFullType()
    return GodSystemConfig.TerminalReliefFullType or "GodSystem.SystemTerminalRelief"
end

local function listSize(list)
    if not list then return 0 end
    if list.size then
        local ok, value = pcall(function() return list:size() end)
        if ok then return math.max(0, math.floor(tonumber(value) or 0)) end
    end
    return type(list) == "table" and #list or 0
end

local function listGet(list, index)
    if not list then return nil end
    if list.get then
        local ok, value = pcall(function() return list:get(index) end)
        return ok and value or nil
    end
    return type(list) == "table" and list[index + 1] or nil
end

local function inventoryItems(inventory)
    if not inventory or not inventory.getItems then return nil end
    local ok, items = pcall(function() return inventory:getItems() end)
    return ok and items or nil
end

local function itemId(item)
    if not item or not item.getID then return nil end
    local ok, value = pcall(function() return item:getID() end)
    return ok and value or nil
end

local function terminalId(terminal)
    local value = itemId(terminal)
    return value ~= nil and tostring(value) or ""
end

local function itemModData(item)
    if not item or not item.getModData then return nil end
    local ok, data = pcall(function() return item:getModData() end)
    return ok and type(data) == "table" and data or nil
end

local function copyTable(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function replaceTable(target, source)
    if type(target) ~= "table" then return end
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source or {}) do target[key] = value end
end

local function readNumber(item, method)
    local value = tonumber(GodSystemB42JavaCalls.value(item, method, nil))
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function readBoolean(item, method)
    local ok, value = GodSystemB42JavaCalls.try(item, method)
    if not ok then return nil end
    return value == true
end

local function resolvePlayer(player)
    if player then return player end
    if getPlayer then
        local ok, value = pcall(getPlayer)
        if ok then return value end
    end
    return nil
end

local function readUnwanted(item, player)
    player = resolvePlayer(player)
    if not item or not item.isUnwanted or not player then return nil end
    local ok, value = pcall(function() return item:isUnwanted(player) end)
    if not ok then return nil end
    return value == true
end

local function containsItem(inventory, target)
    local items = inventoryItems(inventory)
    for i = 0, listSize(items) - 1 do
        if listGet(items, i) == target then return true end
    end
    return false
end

local function removeItem(inventory, item)
    if not inventory or not inventory.Remove or not item then return false end
    local ok = pcall(function() inventory:Remove(item) end)
    return ok and not containsItem(inventory, item)
end

local function addItem(inventory, value)
    if not inventory or not inventory.AddItem then return nil end
    local ok, item = pcall(function() return inventory:AddItem(value) end)
    return ok and item or nil
end

local function reliefItems(inventory)
    local result = {}
    local items = inventoryItems(inventory)
    for i = 0, listSize(items) - 1 do
        local item = listGet(items, i)
        if GodSystemTerminalRelief.isReliefItem(item) then result[#result + 1] = item end
    end
    return result
end

local function captureItem(item, player)
    return {
        item = item,
        id = itemId(item),
        hungChange = readNumber(item, "getHungChange"),
        actualWeight = readNumber(item, "getActualWeight"),
        favorite = readBoolean(item, "isFavorite"),
        unwanted = readUnwanted(item, player),
        modData = copyTable(itemModData(item)),
    }
end

local function restoreItemState(item, state, player)
    if not item or type(state) ~= "table" then return false end
    local ok = true
    if state.hungChange ~= nil and item.setHungChange then
        ok = pcall(function() item:setHungChange(state.hungChange) end) and ok
    end
    if state.favorite ~= nil and item.setFavorite then
        ok = pcall(function() item:setFavorite(state.favorite == true) end) and ok
    end
    if state.unwanted ~= nil and item.setUnwanted then
        player = resolvePlayer(player)
        ok = player ~= nil and pcall(function() item:setUnwanted(player, state.unwanted == true) end) and ok
    end
    replaceTable(itemModData(item), state.modData)
    return ok
end

local function configureItem(item, terminal, reliefLevel, reliefOffset, phase2Level, phase2Offset, totalOffset, player)
    if not item or not item.setHungChange or not item.getActualWeight then return false, false, "unsupported" end
    if not item.setFavorite or not item.setUnwanted then return false, false, "unprotected" end
    player = resolvePlayer(player)
    if not player then return false, false, "playerMissing" end

    local desiredHungChange = totalOffset / 100
    local beforeHung = readNumber(item, "getHungChange")
    local beforeActual = readNumber(item, "getActualWeight")
    local beforeFavorite = readBoolean(item, "isFavorite")
    local beforeUnwanted = readUnwanted(item, player)
    local md = itemModData(item)
    if not md then return false, false, "modDataMissing" end
    local markerKey = GodSystemConfig.TerminalReliefItemMarkerKey or "GodSystemTerminalRelief"
    local ownerKey = GodSystemConfig.TerminalReliefOwnerKey or "GodSystemTerminalReliefOwner"
    local levelKey = GodSystemConfig.TerminalReliefLevelKey or "GodSystemTerminalReliefLevel"
    local offsetKey = GodSystemConfig.TerminalReliefOffsetKey or "GodSystemTerminalReliefOffset"
    local phase2LevelKey = GodSystemConfig.TerminalPhase2LevelKey or "GodSystemTerminalPhase2Level"
    local phase2OffsetKey = GodSystemConfig.TerminalPhase2OffsetKey or "GodSystemTerminalPhase2Offset"
    local compensationOffsetKey = GodSystemConfig.TerminalCompensationOffsetKey or "GodSystemTerminalCompensationOffset"
    local versionKey = GodSystemConfig.TerminalReliefVersionKey or "GodSystemTerminalReliefVersion"
    local changed = math.abs((beforeHung or -999999) - desiredHungChange) > 0.000001
        or beforeActual == nil
        or math.abs(beforeActual + totalOffset) > math.max(EPSILON, totalOffset * 0.0001)
        or beforeFavorite ~= true
        or beforeUnwanted ~= true
        or md[markerKey] ~= true
        or tostring(md[ownerKey] or "") ~= terminalId(terminal)
        or tonumber(md[levelKey]) ~= reliefLevel
        or tonumber(md[offsetKey]) ~= reliefOffset
        or tonumber(md[phase2LevelKey]) ~= phase2Level
        or tonumber(md[phase2OffsetKey]) ~= phase2Offset
        or tonumber(md[compensationOffsetKey]) ~= totalOffset
        or tonumber(md[versionKey]) ~= AUDIT_VERSION

    if not changed then return true, false, nil end

    local ok = pcall(function() item:setHungChange(desiredHungChange) end)
    ok = pcall(function() item:setFavorite(true) end) and ok
    ok = pcall(function() item:setUnwanted(player, true) end) and ok
    if not ok then return false, changed, "writeFailed" end

    md[markerKey] = true
    md[ownerKey] = terminalId(terminal)
    md[levelKey] = reliefLevel
    md[offsetKey] = reliefOffset
    md[phase2LevelKey] = phase2Level
    md[phase2OffsetKey] = phase2Offset
    md[compensationOffsetKey] = totalOffset
    md[versionKey] = AUDIT_VERSION

    local actualWeight = readNumber(item, "getActualWeight")
    if actualWeight == nil or math.abs(actualWeight + totalOffset) > math.max(EPSILON, totalOffset * 0.0001) then
        return false, changed, "weightVerificationFailed"
    end
    if readBoolean(item, "isFavorite") ~= true or readUnwanted(item, player) ~= true then
        return false, changed, "protectionVerificationFailed"
    end
    return true, changed, nil
end

function GodSystemTerminalRelief.getMaxLevel()
    local perLevel = integerSetting("TerminalReliefPerLevel", GodSystemConfig.TerminalReliefPerLevel or 5, 1)
    local maximum = integerSetting("TerminalReliefMaxOffset", GodSystemConfig.TerminalReliefMaxOffset or 2000, 0)
    if maximum <= 0 then return 0 end
    return math.ceil(maximum / perLevel)
end

function GodSystemTerminalRelief.getLevel(data)
    if type(data) ~= "table" then return 0 end
    local level = math.floor(tonumber(data[DATA_FIELD]) or 0)
    level = math.max(0, math.min(level, GodSystemTerminalRelief.getMaxLevel()))
    data[DATA_FIELD] = level
    return level
end

function GodSystemTerminalRelief.setLevel(data, level)
    if type(data) ~= "table" then return false end
    data[DATA_FIELD] = math.max(0, math.min(math.floor(tonumber(level) or 0), GodSystemTerminalRelief.getMaxLevel()))
    return true
end

function GodSystemTerminalRelief.getOffset(data)
    local level = GodSystemTerminalRelief.getLevel(data)
    local perLevel = integerSetting("TerminalReliefPerLevel", GodSystemConfig.TerminalReliefPerLevel or 5, 1)
    local maximum = integerSetting("TerminalReliefMaxOffset", GodSystemConfig.TerminalReliefMaxOffset or 2000, 0)
    return math.min(maximum, level * perLevel)
end

function GodSystemTerminalRelief.getPhase2MaxLevel()
    local maximum = phase2Maximum()
    if maximum <= 0 then return 0 end
    return math.floor(maximum / phase2Step())
end

function GodSystemTerminalRelief.getPhase2Level(data)
    if type(data) ~= "table" then return 0 end
    local level = math.floor(tonumber(data[PHASE2_DATA_FIELD]) or 0)
    level = math.max(0, math.min(level, GodSystemTerminalRelief.getPhase2MaxLevel()))
    data[PHASE2_DATA_FIELD] = level
    return level
end

function GodSystemTerminalRelief.setPhase2Level(data, level)
    if type(data) ~= "table" then return false end
    data[PHASE2_DATA_FIELD] = math.max(0, math.min(math.floor(tonumber(level) or 0), GodSystemTerminalRelief.getPhase2MaxLevel()))
    return true
end

function GodSystemTerminalRelief.getPhase2Offset(data)
    return math.min(phase2Maximum(), GodSystemTerminalRelief.getPhase2Level(data) * phase2Step())
end

function GodSystemTerminalRelief.getTotalOffset(data)
    return GodSystemTerminalRelief.getOffset(data) + GodSystemTerminalRelief.getPhase2Offset(data)
end

function GodSystemTerminalRelief.getPhase2UpgradeInfo(data)
    local level = GodSystemTerminalRelief.getPhase2Level(data)
    local maxLevel = GodSystemTerminalRelief.getPhase2MaxLevel()
    local offset = GodSystemTerminalRelief.getPhase2Offset(data)
    local nextOffset = nil
    local nextCost = nil
    if level < maxLevel then
        nextOffset = math.min(phase2Maximum(), (level + 1) * phase2Step())
        nextCost = integerSetting("TerminalPhase2UpgradeCost", GodSystemConfig.TerminalPhase2UpgradeCost or 2000, 0)
    end
    return {
        upgradeType = "phase2",
        level = level,
        maxLevel = maxLevel,
        offset = offset,
        value = offset,
        nextOffset = nextOffset,
        nextValue = nextOffset,
        nextCost = nextCost,
    }
end

function GodSystemTerminalRelief.getUpgradeInfo(data)
    local level = GodSystemTerminalRelief.getLevel(data)
    local maxLevel = GodSystemTerminalRelief.getMaxLevel()
    local offset = GodSystemTerminalRelief.getOffset(data)
    local nextOffset = nil
    local nextCost = nil
    if level < maxLevel then
        local perLevel = integerSetting("TerminalReliefPerLevel", GodSystemConfig.TerminalReliefPerLevel or 5, 1)
        local maximum = integerSetting("TerminalReliefMaxOffset", GodSystemConfig.TerminalReliefMaxOffset or 2000, 0)
        nextOffset = math.min(maximum, (level + 1) * perLevel)
        nextCost = integerSetting("TerminalReliefUpgradeCost", GodSystemConfig.TerminalReliefUpgradeCost or 2000, 0)
    end
    return {
        upgradeType = "relief",
        level = level,
        maxLevel = maxLevel,
        offset = offset,
        value = offset,
        nextOffset = nextOffset,
        nextValue = nextOffset,
        nextCost = nextCost,
    }
end

function GodSystemTerminalRelief.isReliefItem(item)
    if not item or not item.getFullType then return false end
    local ok, fullType = pcall(function() return item:getFullType() end)
    return ok and tostring(fullType or "") == reliefFullType()
end

function GodSystemTerminalRelief.snapshot(terminal, player)
    if not terminal or not terminal.getInventory then return {} end
    local ok, inventory = pcall(function() return terminal:getInventory() end)
    if not ok or not inventory then return {} end
    local states = {}
    local items = reliefItems(inventory)
    player = resolvePlayer(player)
    for i = 1, #items do states[#states + 1] = captureItem(items[i], player) end
    return { terminal = terminal, inventory = inventory, items = states, player = player }
end

function GodSystemTerminalRelief.restore(snapshot, player)
    if type(snapshot) ~= "table" or not snapshot.inventory then return true, { addedItems = {}, removedItems = {}, items = {} } end
    local inventory = snapshot.inventory
    player = resolvePlayer(player or snapshot.player)
    local expected = snapshot.items or {}
    local keep = {}
    for i = 1, #expected do
        if expected[i].item then keep[expected[i].item] = true end
    end
    local report = { inventory = inventory, addedItems = {}, removedItems = {}, items = {} }
    local ok = true
    local current = reliefItems(inventory)
    for i = #current, 1, -1 do
        if not keep[current[i]] then
            local removed = removeItem(inventory, current[i])
            ok = removed and ok
            if removed then report.removedItems[#report.removedItems + 1] = current[i] end
        end
    end
    for i = 1, #expected do
        local state = expected[i]
        local item = state.item
        if not item or not containsItem(inventory, item) then
            item = addItem(inventory, state.item)
            if not item then item = addItem(inventory, reliefFullType()) end
            if item then report.addedItems[#report.addedItems + 1] = item end
        end
        if not item then
            ok = false
        elseif not restoreItemState(item, state, player) then
            ok = false
        else
            report.items[#report.items + 1] = item
        end
    end
    return ok, report
end

function GodSystemTerminalRelief.ensureTerminal(terminal, data, player)
    if not terminal or not terminal.getInventory then return false, { reason = "missing" } end
    if terminal.getFullType then
        local okType, fullType = pcall(function() return terminal:getFullType() end)
        if not okType or tostring(fullType or "") ~= (GodSystemConfig.AutoRecyclerFullType or "GodSystem.SystemSpaceTerminal") then
            return false, { reason = "wrongTerminal" }
        end
    end
    local okInventory, inventory = pcall(function() return terminal:getInventory() end)
    if not okInventory or not inventory then return false, { reason = "inventoryMissing" } end

    if isClient and isClient() and not (isServer and isServer()) then
        return true, {
            inventory = inventory,
            level = GodSystemTerminalRelief.getLevel(data),
            maxLevel = GodSystemTerminalRelief.getMaxLevel(),
            reliefLevel = GodSystemTerminalRelief.getLevel(data),
            reliefOffset = GodSystemTerminalRelief.getOffset(data),
            phase2Level = GodSystemTerminalRelief.getPhase2Level(data),
            phase2MaxLevel = GodSystemTerminalRelief.getPhase2MaxLevel(),
            phase2Offset = GodSystemTerminalRelief.getPhase2Offset(data),
            offset = GodSystemTerminalRelief.getTotalOffset(data),
            addedItems = {}, removedItems = {}, items = {}, clientReadOnly = true,
        }
    end

    player = resolvePlayer(player)
    local before = GodSystemTerminalRelief.snapshot(terminal, player)
    local reliefLevel = GodSystemTerminalRelief.getLevel(data)
    local reliefOffset = GodSystemTerminalRelief.getOffset(data)
    local phase2Level = GodSystemTerminalRelief.getPhase2Level(data)
    local phase2Offset = GodSystemTerminalRelief.getPhase2Offset(data)
    local offset = GodSystemTerminalRelief.getTotalOffset(data)
    local report = {
        inventory = inventory,
        level = reliefLevel,
        maxLevel = GodSystemTerminalRelief.getMaxLevel(),
        reliefLevel = reliefLevel,
        reliefOffset = reliefOffset,
        phase2Level = phase2Level,
        phase2MaxLevel = GodSystemTerminalRelief.getPhase2MaxLevel(),
        phase2Offset = phase2Offset,
        offset = offset,
        addedItems = {},
        removedItems = {},
        items = {},
        removedDuplicates = 0,
    }
    local items = reliefItems(inventory)

    if offset <= 0 then
        for i = #items, 1, -1 do
            if not removeItem(inventory, items[i]) then
                GodSystemTerminalRelief.restore(before)
                return false, { reason = "removeFailed", offset = offset }
            end
            report.removedItems[#report.removedItems + 1] = items[i]
        end
        report.removedDuplicates = #items
        return true, report
    end

    local relief = items[1]
    if not relief then
        relief = addItem(inventory, reliefFullType())
        if not relief then
            GodSystemTerminalRelief.restore(before)
            return false, { reason = "createFailed", offset = offset }
        end
        report.addedItems[#report.addedItems + 1] = relief
    end
    for i = #items, 2, -1 do
        if not removeItem(inventory, items[i]) then
            GodSystemTerminalRelief.restore(before)
            return false, { reason = "duplicateRemoveFailed", offset = offset }
        end
        report.removedItems[#report.removedItems + 1] = items[i]
        report.removedDuplicates = report.removedDuplicates + 1
    end

    local configured, changed, reason = configureItem(relief, terminal, reliefLevel, reliefOffset, phase2Level, phase2Offset, offset, player)
    if not configured then
        GodSystemTerminalRelief.restore(before)
        return false, { reason = reason or "configureFailed", offset = offset }
    end
    report.reliefItem = relief
    if changed or #report.addedItems > 0 then report.items[#report.items + 1] = relief end
    return true, report
end

function GodSystemTerminalRelief.removeEscapedFromPlayer(player, ownedTerminal)
    local root = player and player.getInventory and player:getInventory() or nil
    if not root then return 0, {} end
    local allowed = nil
    if ownedTerminal and ownedTerminal.getInventory then
        local ok, inventory = pcall(function() return ownedTerminal:getInventory() end)
        if ok then allowed = inventory end
    end
    local removed = {}
    local seen = {}
    local function scan(inventory)
        if not inventory or seen[inventory] then return end
        seen[inventory] = true
        local items = inventoryItems(inventory)
        for i = listSize(items) - 1, 0, -1 do
            local item = listGet(items, i)
            if GodSystemTerminalRelief.isReliefItem(item) and inventory ~= allowed then
                if removeItem(inventory, item) then removed[#removed + 1] = { item = item, container = inventory } end
            elseif item and item.getInventory then
                local ok, child = pcall(function() return item:getInventory() end)
                if ok and child then scan(child) end
            end
        end
    end
    scan(root)
    return #removed, removed
end

return GodSystemTerminalRelief
