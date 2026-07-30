GodSystemProgressionPlatformSupport = GodSystemProgressionPlatformSupport or {}

local Support = GodSystemProgressionPlatformSupport

function Support.finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

function Support.number(value, fallback, minimum, maximum)
    if not Support.finite(value) then value = fallback end
    value = tonumber(value)
    if not Support.finite(value) then return nil end
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

function Support.integer(value, fallback, minimum, maximum)
    value = Support.number(value, fallback, minimum, maximum)
    if value == nil then return nil end
    value = math.floor(value)
    if math.abs(value) > 9007199254740991 then return nil end
    return value
end

function Support.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Support.copy(key, seen)] = Support.copy(item, seen) end
    return result
end

function Support.call(target, methodName, ...)
    if not target or type(target[methodName]) ~= "function" then return false, nil end
    return pcall(target[methodName], target, ...)
end

function Support.read(target, methods, fallback, ...)
    for index = 1, #(methods or {}) do
        local ok, value = Support.call(target, methods[index], ...)
        if ok and value ~= nil then return value end
    end
    return fallback
end

function Support.write(target, methods, ...)
    for index = 1, #(methods or {}) do
        if target and type(target[methods[index]]) == "function" then
            local ok = pcall(target[methods[index]], target, ...)
            if ok then return true end
        end
    end
    return false
end

function Support.identity(actor, binding)
    if binding and type(binding.identity) == "function" then
        local ok, value = pcall(binding.identity, actor)
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    local username = Support.read(actor, { "getUsername" }, nil)
    if username ~= nil and tostring(username) ~= "" then return "user:" .. tostring(username) end
    local onlineId = Support.read(actor, { "getOnlineID" }, nil)
    if onlineId ~= nil then return "online:" .. tostring(onlineId) end
    if type(actor) == "table" and actor.id ~= nil then return "actor:" .. tostring(actor.id) end
    return "actor:local"
end

function Support.config(context, defaults)
    local result = Support.copy(defaults or {})
    local binding = type(context and context.binding) == "table" and context.binding or {}
    local source = type(binding.config) == "table" and binding.config or binding
    for key, value in pairs(source) do
        if type(value) ~= "function" then result[key] = Support.copy(value) end
    end
    return result, binding
end

function Support.values(list)
    local result = {}
    if not list then return result end
    if type(list.size) == "function" and type(list.get) == "function" then
        local ok, count = pcall(list.size, list)
        count = ok and Support.integer(count, 0, 0) or 0
        for index = 0, count - 1 do
            local got, value = pcall(list.get, list, index)
            if got then result[#result + 1] = value end
        end
    elseif type(list) == "table" then
        local source = type(list.values) == "table" and list.values or list
        for index = 1, #source do result[#result + 1] = source[index] end
    end
    return result
end

function Support.modData(target)
    local ok, value = Support.call(target, "getModData")
    return ok and type(value) == "table" and value or nil
end

function Support.writeNumber(target, setter, getter, value, epsilon)
    value = Support.number(value, nil)
    epsilon = Support.number(epsilon, 0.0001, 0)
    if value == nil then return false, "valueInvalid" end
    local before = Support.number(Support.read(target, { getter }, nil), nil)
    if before == nil then return false, "readFailed" end
    if math.abs(before - value) <= epsilon then return true, false end
    if not Support.write(target, { setter }, value) then return false, "writeFailed" end
    local after = Support.number(Support.read(target, { getter }, nil), nil)
    if after == nil or math.abs(after - value) > epsilon then return false, "verificationFailed" end
    return true, true
end

function Support.lifecycle(moduleId, public, counters)
    local instance = {
        started = false,
        public = public or {},
        counters = counters or {},
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
    return instance
end

return Support
