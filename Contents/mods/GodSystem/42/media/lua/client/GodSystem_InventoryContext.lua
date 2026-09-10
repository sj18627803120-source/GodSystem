-- Shared inventory context snapshot and dispatcher.
-- Each item-bar context menu is expanded once, then delivered to the feature handlers.
GodSystemInventoryContext = GodSystemInventoryContext or {}

local Dispatcher = GodSystemInventoryContext
Dispatcher.handlers = Dispatcher.handlers or {}
Dispatcher.order = Dispatcher.order or {}
Dispatcher._installed = false
Dispatcher._shopSetRevision = nil
Dispatcher._shopSet = nil
Dispatcher.BULK_THRESHOLD = 200

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

local function append(result, seen, item)
    if not item or not instanceof(item, "InventoryItem") then return end
    if seen[item] then return end
    seen[item] = true
    local typeName = fullType(item)
    local ok, source = pcall(function() return item:getContainer() end)
    result.items[#result.items + 1] = item
    result.fullTypes[item] = typeName
    result.sources[item] = ok and source or false
    local group = result.types[typeName] or { count = 0, item = item }
    result.types[typeName] = group
    group.count = group.count + 1
end

local function expand(values)
    local snapshot = { __godSystemInventorySnapshot = true, items = {}, entries = {}, byId = {}, fullTypes = {}, sources = {}, types = {} }
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

-- Identity/sprite data is only needed by recycling, never by unrelated menu handlers.
function Dispatcher.getEntry(snapshot, index)
    if snapshot.entries[index] then return snapshot.entries[index] end
    local item = snapshot.items[index]
    if not item then return nil end
    local id = itemId(item)
    local sprite = worldSprite(item)
    local typeName = snapshot.fullTypes[item]
    local meta = { item = item, id = id, fullType = typeName, worldSprite = sprite,
        source = snapshot.sources[item], variantKey = GodSystemShopVariants.getKey(typeName, sprite) }
    snapshot.entries[index] = meta
    if id then
        if snapshot.byId[id] and snapshot.byId[id].item ~= item then snapshot.invalid = true end
        snapshot.byId[id] = meta
    else
        snapshot.invalid = true
    end
    return meta
end

function Dispatcher.getEntries(snapshot)
    for i = 1, #snapshot.items do Dispatcher.getEntry(snapshot, i) end
    return snapshot.entries
end

function Dispatcher.singleMatching(snapshot, matches)
    local selected
    for typeName, group in pairs(snapshot.types) do
        if matches(typeName) then
            if selected or group.count ~= 1 then return nil end
            selected = group.item
        end
    end
    return selected
end

-- Cheap ancestry query already used by the lottery menu; never recurse through unrelated items.
function Dispatcher.isCarried(player, item)
    local container = item and item.getContainer and item:getContainer() or nil
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not container or not inventory then return false end
    if container == inventory then return true end
    if container.isInCharacterInventory then
        local ok, carried = pcall(function() return container:isInCharacterInventory(player) end)
        return ok and carried == true
    end
    return false
end

function Dispatcher.createSnapshot(playerNum, values)
    local snapshot = expand(values)
    snapshot.playerNum = playerNum
    snapshot.bulk = #snapshot.items > Dispatcher.BULK_THRESHOLD
    return snapshot
end

function Dispatcher.invalidateEconomyCache()
    Dispatcher._shopSetRevision = nil
    Dispatcher._shopSet = nil
end

function Dispatcher.getConfiguredShopKeySet()
    local current = GodSystemItemConfig and GodSystemItemConfig.Current or nil
    local revision = tonumber(current and current.economyRevision or 1) or 1
    if not Dispatcher._shopSet or Dispatcher._shopSetRevision ~= revision or Dispatcher._shopSetSource ~= current then
        local source = GodSystemApp and GodSystemApp.services and GodSystemApp.services.runtime
        local values = source and source.getConfiguredShopKeySet and source.getConfiguredShopKeySet() or {}
        Dispatcher._shopSet = {}
        for key, value in pairs(values) do Dispatcher._shopSet[key] = value end
        Dispatcher._shopSetRevision = revision
        Dispatcher._shopSetSource = current
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
