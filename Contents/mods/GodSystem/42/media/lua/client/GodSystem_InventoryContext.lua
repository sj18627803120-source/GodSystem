-- Shared inventory context snapshot and dispatcher.
-- Each item-bar context menu is expanded once, then delivered to the feature handlers.
GodSystemInventoryContext = GodSystemInventoryContext or {}

local Dispatcher = GodSystemInventoryContext
Dispatcher.handlers = Dispatcher.handlers or {}
Dispatcher.order = Dispatcher.order or {}
Dispatcher._installed = false
Dispatcher._shopSetRevision = nil
Dispatcher._shopSet = nil

local function itemId(item)
    if not item or not item.getID then return nil end
    local ok, value = pcall(function() return item:getID() end)
    return ok and value ~= nil and tostring(value) or nil
end

local function fullType(item)
    if not item or not item.getFullType then return "" end
    local ok, value = pcall(function() return item:getFullType() end)
    return ok and tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function worldSprite(item)
    if not item or not item.getWorldSprite then return nil end
    local ok, value = pcall(function() return item:getWorldSprite() end)
    value = ok and tostring(value or "") or ""
    return value ~= "" and value or nil
end

local function variantKey(typeName, item)
    if GodSystemShopVariants and GodSystemShopVariants.getKey then
        local ok, value = pcall(function() return GodSystemShopVariants.getKey(typeName, item) end)
        if ok and value then return tostring(value) end
    end
    return typeName
end

local function append(result, seen, item)
    if not item or not instanceof(item, "InventoryItem") then return end
    local id = itemId(item)
    if not id or seen[id] then return end
    seen[id] = true
    local typeName = fullType(item)
    local meta = {
        item = item,
        id = id,
        fullType = typeName,
        worldSprite = worldSprite(item),
        variantKey = variantKey(typeName, item),
    }
    if GodSystemLottery and GodSystemLottery.isTicket then
        local ok, value = pcall(function() return GodSystemLottery.isTicket(typeName) end)
        meta.isLotteryTicket = ok and value == true or false
    end
    if GodSystemMaintenance and GodSystemMaintenance.isUtilityItem then
        local ok, value = pcall(function() return GodSystemMaintenance.isUtilityItem(item) end)
        meta.isMaintenanceUtility = ok and value == true or false
    end
    if GodSystemAutoLoader and GodSystemAutoLoader.isLoader then
        local ok, value = pcall(function() return GodSystemAutoLoader.isLoader(item) end)
        meta.isAutoLoader = ok and value == true or false
    end
    result.items[#result.items + 1] = item
    result.entries[#result.entries + 1] = meta
    result.byId[id] = meta
end

local function expand(values)
    local snapshot = { __godSystemInventorySnapshot = true, items = {}, entries = {}, byId = {} }
    local seen = {}
    for _, value in ipairs(values or {}) do
        if instanceof(value, "InventoryItem") then
            append(snapshot, seen, value)
        elseif value and value.items then
            for _, item in ipairs(value.items) do append(snapshot, seen, item) end
        end
    end
    return snapshot
end

function Dispatcher.createSnapshot(playerNum, values)
    local snapshot = expand(values)
    snapshot.playerNum = playerNum
    return snapshot
end

function Dispatcher.invalidateEconomyCache()
    Dispatcher._shopSetRevision = nil
    Dispatcher._shopSet = nil
end

function Dispatcher.getConfiguredShopKeySet()
    local current = GodSystemItemConfig and GodSystemItemConfig.Current or nil
    local revision = tonumber(current and current.economyRevision or 1) or 1
    if not Dispatcher._shopSet or Dispatcher._shopSetRevision ~= revision then
        local source = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime
        local values = source and source.getConfiguredShopKeySet and source.getConfiguredShopKeySet() or {}
        Dispatcher._shopSet = {}
        for key, value in pairs(values) do Dispatcher._shopSet[key] = value end
        Dispatcher._shopSetRevision = revision
    end
    return Dispatcher._shopSet
end

function Dispatcher.register(name, handler)
    if type(name) ~= "string" or name == "" or type(handler) ~= "function" then return false end
    if not Dispatcher.handlers[name] then Dispatcher.order[#Dispatcher.order + 1] = name end
    Dispatcher.handlers[name] = handler
    Dispatcher.install()
    return true
end

function Dispatcher.install()
    if Dispatcher._installed or not Events or not Events.OnFillInventoryObjectContextMenu then return end
    Events.OnFillInventoryObjectContextMenu.Remove(Dispatcher.onFillInventoryObjectContextMenu)
    Events.OnFillInventoryObjectContextMenu.Add(Dispatcher.onFillInventoryObjectContextMenu)
    Dispatcher._installed = true
end

function Dispatcher.onFillInventoryObjectContextMenu(playerNum, context, values)
    local snapshot = Dispatcher.createSnapshot(playerNum, values)
    if #snapshot.items <= 0 then return end
    for i = 1, #Dispatcher.order do
        local handler = Dispatcher.handlers[Dispatcher.order[i]]
        if handler then pcall(handler, playerNum, context, snapshot) end
    end
end

Dispatcher.install()
return Dispatcher
