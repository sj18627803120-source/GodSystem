GodSystemApp = GodSystemApp or {}
GodSystemApp.services = GodSystemApp.services or {}

local Service = {}
Service.__index = Service

local function playerKey(playerNum)
    return tostring(math.floor(tonumber(playerNum) or 0))
end

function Service:setViewModelProvider(provider)
    assert(type(provider) == "function", "view model provider must be a function")
    self.viewModelProvider = provider
    return self
end

function Service:setExecutor(executor)
    assert(type(executor) == "function", "executor must be a function")
    self.executor = executor
    return self
end

function Service:getViewModel(playerNum)
    if not self.viewModelProvider then return {} end
    local value = self.viewModelProvider(playerNum)
    return type(value) == "table" and value or {}
end

function Service:execute(playerNum, intent, payload, callback)
    if not self.executor then
        local result = {
            ok = false,
            code = "ServiceIntentUnsupported",
            args = { service = self.name, intent = tostring(intent or "") },
            data = {},
        }
        if callback then callback(result) end
        return nil
    end
    return self.executor(playerNum, intent, payload or {}, callback)
end

function Service:subscribe(playerNum, listener)
    assert(type(listener) == "function", "listener must be a function")
    local key = playerKey(playerNum)
    self.listeners[key] = self.listeners[key] or {}
    local bucket = self.listeners[key]
    bucket[#bucket + 1] = listener
    local active = true
    return function()
        if not active then return end
        active = false
        for i = #bucket, 1, -1 do
            if bucket[i] == listener then table.remove(bucket, i) end
        end
    end
end

function Service:publish(playerNum, topic, data)
    local bucket = self.listeners[playerKey(playerNum)] or {}
    local event = { topic = tostring(topic or "changed"), data = data or {} }
    for i = 1, #bucket do bucket[i](event) end
end

function GodSystemApp.createService(name)
    local key = tostring(name or "")
    assert(key ~= "", "service name is required")
    local service = setmetatable({ name = key, listeners = {} }, Service)
    GodSystemApp.services[key] = service
    return service
end

function GodSystemApp.getService(name)
    return GodSystemApp.services[tostring(name or "")]
end
