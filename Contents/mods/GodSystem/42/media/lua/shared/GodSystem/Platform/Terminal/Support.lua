GodSystemTerminalPlatformSupport = GodSystemTerminalPlatformSupport or {}

local Support = GodSystemTerminalPlatformSupport

function Support.finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

function Support.number(value, fallback)
    if not Support.finite(value) then value = fallback end
    value = tonumber(value)
    return Support.finite(value) and value or nil
end

function Support.integer(value, fallback, minimum, maximum)
    value = math.floor(Support.number(value, fallback or 0) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function Support.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[Support.copy(key, seen)] = Support.copy(child, seen)
    end
    return result
end

function Support.call(target, methodName, ...)
    if not target or type(target[methodName]) ~= "function" then return false, nil end
    return pcall(target[methodName], target, ...)
end

function Support.read(target, methods, fallback, ...)
    for index = 1, #(methods or {}) do
        local called, value = Support.call(target, methods[index], ...)
        if called and value ~= nil then return value end
    end
    return fallback
end

function Support.write(target, methods, ...)
    for index = 1, #(methods or {}) do
        if target and type(target[methods[index]]) == "function" then
            local called = pcall(target[methods[index]], target, ...)
            if called then return true end
        end
    end
    return false
end

function Support.binding(context)
    return type(context and context.binding) == "table" and context.binding or {}
end

function Support.api(binding, name)
    if type(binding) == "table" and type(binding[name]) == "function" then
        return binding[name]
    end
    return type(_G) == "table" and _G[name] or nil
end

function Support.identity(actor, binding)
    if type(binding.identity) == "function" then
        local called, value = pcall(binding.identity, actor)
        if called and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    local username = Support.read(actor, { "getUsername" }, nil)
    if username ~= nil and tostring(username) ~= "" then return "user:" .. tostring(username) end
    local onlineId = Support.read(actor, { "getOnlineID" }, nil)
    if onlineId ~= nil then return "online:" .. tostring(onlineId) end
    if type(actor) == "table" and actor.id ~= nil then return "actor:" .. tostring(actor.id) end
    return "actor:local"
end

function Support.modData(target)
    local called, value = Support.call(target, "getModData")
    return called and type(value) == "table" and value or nil
end

function Support.itemId(item)
    local value = Support.read(item, { "getID" }, nil)
    return value ~= nil and tostring(value) or nil
end

function Support.fullType(item)
    return tostring(Support.read(item, { "getFullType" }, "") or "")
end

function Support.values(list)
    local result = {}
    if not list then return result end
    if type(list.size) == "function" and type(list.get) == "function" then
        local called, count = pcall(list.size, list)
        count = called and Support.integer(count, 0, 0) or 0
        for index = 0, count - 1 do
            local got, value = pcall(list.get, list, index)
            if got and value then result[#result + 1] = value end
        end
    elseif type(list) == "table" then
        local source = type(list.values) == "table" and list.values or list
        for index = 1, #source do result[#result + 1] = source[index] end
    end
    return result
end

function Support.items(container)
    return Support.values(Support.read(container, { "getItems" }, nil))
end

function Support.contains(container, item)
    if not container or not item then return false end
    local expectedId = Support.itemId(item)
    local rows = Support.items(container)
    for index = 1, #rows do
        if rows[index] == item then return true end
        if expectedId and Support.itemId(rows[index]) == expectedId then return true end
    end
    return false
end

function Support.child(item)
    return Support.read(item, { "getInventory" }, nil)
end

function Support.findRecursive(container, predicate, maximumDepth)
    local seen = {}
    local function visit(current, depth)
        if not current or seen[current] or depth > (maximumDepth or 32) then return nil, nil end
        seen[current] = true
        local rows = Support.items(current)
        for index = 1, #rows do
            local item = rows[index]
            if predicate(item, current) then return item, current end
            local found, owner = visit(Support.child(item), depth + 1)
            if found then return found, owner end
        end
        return nil, nil
    end
    return visit(container, 0)
end

function Support.add(container, value)
    if not container then return nil end
    local called, item = Support.call(container, "AddItem", value)
    if not called or not item then return nil end
    return Support.contains(container, item) and item or nil
end

function Support.remove(container, item)
    if not container or not item or not Support.contains(container, item) then return false end
    if not Support.write(container, { "Remove" }, item) then return false end
    return not Support.contains(container, item)
end

function Support.syncAdd(binding, container, item)
    local callback = Support.api(binding, "sendAddItemToContainer")
    if type(callback) == "function" then
        local called, value = pcall(callback, container, item)
        if not called or value == false then return false end
    end
    Support.write(container, { "setDrawDirty" }, true)
    return true
end

function Support.syncRemove(binding, container, item)
    local callback = Support.api(binding, "sendRemoveItemFromContainer")
    if type(callback) == "function" then
        local called, value = pcall(callback, container, item)
        if not called or value == false then return false end
    end
    Support.write(container, { "setDrawDirty" }, true)
    return true
end

function Support.ownedBy(actor, item)
    local root = Support.read(actor, { "getInventory" }, nil)
    if not root or not item then return false end
    local current, seen = item, {}
    for _ = 1, 34 do
        if not current or seen[current] then return false end
        seen[current] = true
        local container = Support.read(current, { "getContainer" }, nil)
        if not container then return false end
        if container == root then return true end
        current = Support.read(container, { "getContainingItem" }, nil)
    end
    return false
end

function Support.writeNumber(target, setter, getter, value)
    value = Support.number(value, nil)
    if value == nil then return false, "valueInvalid" end
    local before = Support.number(Support.read(target, { getter }, nil), nil)
    if before == nil then return false, "readFailed" end
    if math.abs(before - value) <= 0.0001 then return true, false end
    if not Support.write(target, { setter }, value) then return false, "writeFailed" end
    local after = Support.number(Support.read(target, { getter }, nil), nil)
    if after == nil or math.abs(after - value) > 0.0001 then
        return false, "verificationFailed"
    end
    return true, true
end

function Support.lifecycle(moduleId, public, counters)
    local instance = {
        started = false,
        public = public or {},
        counters = counters or { failures = 0 },
    }
    function instance:start() self.started = true return true end
    function instance:stop() self.started = false return true end
    function instance:health()
        return {
            ok = self.started and (self.counters.failures or 0) == 0,
            code = (self.counters.failures or 0) > 0 and "adapterFailure"
                or (self.started and "healthy" or "stopped"),
            data = Support.copy(self.counters),
            moduleId = moduleId,
        }
    end
    if type(instance.public.health) ~= "function" then
        instance.public.health = function() return instance:health() end
    end
    return instance
end

return Support
