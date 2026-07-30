GodSystemCommercePlatformSupport = GodSystemCommercePlatformSupport or {}

local Support = GodSystemCommercePlatformSupport

function Support.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[Support.copy(key, seen)] = Support.copy(item, seen)
    end
    return result
end

function Support.safeCall(target, methodName, fallback, ...)
    if not target or type(target[methodName]) ~= "function" then return fallback end
    local ok, value = pcall(target[methodName], target, ...)
    if ok then return value end
    return fallback
end

function Support.integer(value, fallback, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        value = fallback
    end
    value = math.floor(tonumber(value) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Support.itemId(item)
    local value = Support.safeCall(item, "getID", nil)
    return value ~= nil and tostring(value) or nil
end

function Support.fullType(item)
    local value = Support.safeCall(item, "getFullType", nil)
    value = tostring(value or "")
    return value ~= "" and value or nil
end

function Support.worldSprite(value)
    if type(value) == "string" then return value ~= "" and value or nil end
    local sprite = Support.safeCall(value, "getWorldSprite", nil)
    sprite = tostring(sprite or "")
    return sprite ~= "" and sprite or nil
end

function Support.itemsArray(container)
    local result = {}
    local items = Support.safeCall(container, "getItems", nil)
    if not items then return result end
    if type(items.size) == "function" and type(items.get) == "function" then
        for index = 0, items:size() - 1 do result[#result + 1] = items:get(index) end
    elseif type(items) == "table" then
        local source = items.values or items
        for index = 1, #source do result[#result + 1] = source[index] end
    end
    return result
end

function Support.playerInventory(actor)
    return Support.safeCall(actor, "getInventory", nil)
end

function Support.childContainer(item)
    return Support.safeCall(item, "getInventory", nil)
end

function Support.contains(container, item)
    local wantedId = Support.itemId(item)
    if not wantedId then return false end
    local values = Support.itemsArray(container)
    for index = 1, #values do
        if Support.itemId(values[index]) == wantedId then return true end
    end
    return false
end

function Support.scriptItem(fullType)
    if type(getScriptManager) ~= "function" then return nil end
    local okManager, manager = pcall(getScriptManager)
    if not okManager or not manager or type(manager.FindItem) ~= "function" then return nil end
    local okItem, item = pcall(manager.FindItem, manager, tostring(fullType or ""))
    return okItem and item or nil
end

function Support.moduleName(fullType)
    return tostring(fullType or ""):match("^([^%.]+)%.")
end

function Support.markAdded(container, item)
    if type(sendAddItemToContainer) == "function" then
        pcall(sendAddItemToContainer, container, item)
    end
end

function Support.markRemoved(container, item)
    if type(sendRemoveItemFromContainer) == "function" then
        pcall(sendRemoveItemFromContainer, container, item)
    end
end

return Support
