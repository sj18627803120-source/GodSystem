GodSystemAutoLoaderPlatformSupport = GodSystemAutoLoaderPlatformSupport or {}

local Support = GodSystemAutoLoaderPlatformSupport

Support.FullType = "GodSystem.SystemAutoLoader"
Support.DataKey = "GodSystemAutoLoader"
Support.OperationKey = "GodSystemAutoLoaderOperations"

function Support.safeCall(target, methodName, fallback, ...)
    if not target or type(target[methodName]) ~= "function" then return fallback end
    local ok, value = pcall(target[methodName], target, ...)
    if ok then return value end
    return fallback
end

function Support.itemId(item)
    local value = Support.safeCall(item, "getID", nil)
    return value ~= nil and tostring(value) or nil
end

function Support.fullType(item)
    local value = Support.safeCall(item, "getFullType", nil)
    value = value ~= nil and tostring(value) or ""
    return value ~= "" and value or nil
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

function Support.childContainer(item)
    return Support.safeCall(item, "getInventory", nil)
end

function Support.playerInventory(actor)
    return Support.safeCall(actor, "getInventory", nil)
end

function Support.containerContains(container, item)
    local wantedId = Support.itemId(item)
    if not wantedId then return false end
    local values = Support.itemsArray(container)
    for index = 1, #values do
        if Support.itemId(values[index]) == wantedId then return true end
    end
    return false
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

function Support.nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return math.floor(tonumber(value)) end
    end
    return math.floor((os and os.time and os.time() or 0) * 1000)
end

return Support
