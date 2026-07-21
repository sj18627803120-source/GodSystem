GodSystemLegacyCompressionCleanup = GodSystemLegacyCompressionCleanup or {}

local BASE_WEIGHT_KEY = "GodSystemCompressionBaseActualWeight"
local BASE_INPUT_KEY = "GodSystemCompressionBaseInputWeight"
local BASE_CUSTOM_KEY = "GodSystemCompressionBaseCustomWeight"
local LAST_WEIGHT_KEY = "GodSystemCompressionLastAppliedWeight"
local LAST_INPUT_KEY = "GodSystemCompressionLastInputWeight"
local OWNER_KEY = "GodSystemCompressionTerminalId"
local VERSION_KEY = "GodSystemCompressionVersion"
local MIGRATION_VERSION = 1
local TERMINAL_MIGRATION_KEY = "GodSystemLegacyCompressionCleanupVersion"
local MAX_DEPTH = 32
local EPSILON = 0.0001

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function modData(item)
    if not item or not item.getModData then return nil end
    local ok, value = pcall(function() return item:getModData() end)
    return ok and type(value) == "table" and value or nil
end

local function actualWeight(item)
    if not item or not item.getActualWeight then return nil end
    local ok, value = pcall(function() return item:getActualWeight() end)
    value = ok and tonumber(value) or nil
    return finite(value) and value >= 0 and value or nil
end

local function customWeight(item)
    if not item or not item.isCustomWeight then return false end
    local ok, value = pcall(function() return item:isCustomWeight() end)
    return ok and value == true
end

local function clearMarkers(data)
    data[BASE_WEIGHT_KEY] = nil
    data[BASE_INPUT_KEY] = nil
    data[BASE_CUSTOM_KEY] = nil
    data[LAST_WEIGHT_KEY] = nil
    data[LAST_INPUT_KEY] = nil
    data[OWNER_KEY] = nil
    data[VERSION_KEY] = nil
end

function GodSystemLegacyCompressionCleanup.restoreItem(item)
    local data = modData(item)
    local expected = data and tonumber(data[BASE_WEIGHT_KEY]) or nil
    if not finite(expected) or expected < 0 then return false, "notTagged" end
    local input = tonumber(data[BASE_INPUT_KEY])
    if not finite(input) or input < 0 then input = expected end
    local expectedCustom = data[BASE_CUSTOM_KEY] == true
    if not item.setActualWeight or not item.setCustomWeight then return false, "unsupported" end

    local appliedInput = input
    local ok = pcall(function()
        item:setCustomWeight(true)
        for _ = 1, 3 do
            item:setActualWeight(appliedInput)
            local after = actualWeight(item)
            if after and math.abs(after - expected) <= math.max(EPSILON, math.abs(expected) * 0.001) then break end
            if not after then break end
            appliedInput = appliedInput + (expected - after)
            if not finite(appliedInput) or appliedInput < 0 then break end
        end
        if not expectedCustom then item:setCustomWeight(false) end
    end)
    local after = actualWeight(item)
    local tolerance = math.max(EPSILON, math.abs(expected) * 0.001)
    if not ok or not after or math.abs(after - expected) > tolerance or customWeight(item) ~= expectedCustom then
        return false, "restoreFailed"
    end
    clearMarkers(data)
    return true, "restored"
end

local function visitInventory(inventory, state, depth)
    if not inventory or not inventory.getItems or depth > MAX_DEPTH or state.seen[inventory] then return end
    state.seen[inventory] = true
    local ok, items = pcall(function() return inventory:getItems() end)
    if not ok or not items or not items.size or not items.get then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and not state.items[item] then
            state.items[item] = true
            local data = modData(item)
            if data and finite(data[BASE_WEIGHT_KEY]) then
                local restored = GodSystemLegacyCompressionCleanup.restoreItem(item)
                if restored then
                    state.restored[#state.restored + 1] = item
                else
                    state.failed = state.failed + 1
                end
            end
            if item.getInventory then
                local childOk, child = pcall(function() return item:getInventory() end)
                if childOk and child then visitInventory(child, state, depth + 1) end
            end
        end
    end
end

function GodSystemLegacyCompressionCleanup.restoreInventory(inventory)
    if not inventory or not inventory.getItems then return false, {}, 1 end
    local readable, items = pcall(function() return inventory:getItems() end)
    if not readable or not items or not items.size or not items.get then return false, {}, 1 end
    local state = { seen = {}, items = {}, restored = {}, failed = 0 }
    visitInventory(inventory, state, 0)
    return state.failed == 0, state.restored, state.failed
end

function GodSystemLegacyCompressionCleanup.restoreTerminal(terminal)
    if not terminal or not terminal.getInventory then return true, {}, 0 end
    local terminalData = modData(terminal)
    if terminalData and (tonumber(terminalData[TERMINAL_MIGRATION_KEY]) or 0) >= MIGRATION_VERSION then
        return true, {}, 0
    end
    local ok, inventory = pcall(function() return terminal:getInventory() end)
    if not ok or not inventory then return false, {}, 1 end
    local restoredOk, restored, failed = GodSystemLegacyCompressionCleanup.restoreInventory(inventory)
    if restoredOk and terminalData then terminalData[TERMINAL_MIGRATION_KEY] = MIGRATION_VERSION end
    return restoredOk, restored, failed
end

function GodSystemLegacyCompressionCleanup.restorePlayerInventory(player, data)
    if type(data) == "table" and (tonumber(data.legacyCompressionMigrationVersion) or 0) >= MIGRATION_VERSION then
        return true, {}, 0, false
    end
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory then return false, {}, 1, false end
    local ok, restored, failed = GodSystemLegacyCompressionCleanup.restoreInventory(inventory)
    if ok and type(data) == "table" then
        data.legacyCompressionMigrationVersion = MIGRATION_VERSION
        data.autoRecyclerCompressionLevel = nil
    end
    return ok, restored, failed, true
end

return GodSystemLegacyCompressionCleanup
