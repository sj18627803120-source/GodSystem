require "GodSystem/Core/Result"
require "GodSystem/Runtime/Protocol422012"

GodSystemClientGateway = GodSystemClientGateway or {}

local Gateway = GodSystemClientGateway

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

function Gateway.new(options)
    options = type(options) == "table" and options or {}
    local runtime = options.runtime
    local remote = options.remote
    local actor = type(options.actor) == "function" and options.actor or function() return nil end
    local protocol = tostring(options.protocolVersion or GodSystemProtocol422012.Version)
    local onResult = options.onResult
    local observers = {}
    if type(onResult) == "function" then observers[1] = onResult end
    local sequence = 0
    local instance = {
        cache = {},
        pending = {},
        completed = 0,
        failures = 0,
    }

    local function nextId(action)
        sequence = sequence + 1
        return table.concat({
            "ui",
            tostring(action or ""):gsub("[^%w%._%-]", "_"),
            tostring(sequence),
        }, ":")
    end

    local function complete(action, result, callback)
        result = GodSystemResult.normalize(result, "runtime.client")
        instance.cache[action] = copy(result)
        instance.pending[action] = nil
        instance.completed = instance.completed + 1
        if result.ok ~= true then instance.failures = instance.failures + 1 end
        if type(callback) == "function" then callback(copy(result)) end
        for index = 1, #observers do
            observers[index](action, copy(result))
        end
        return result
    end

    function instance:request(action, args, requestOptions)
        action = tostring(action or "")
        requestOptions = type(requestOptions) == "table" and requestOptions or {}
        if type(GodSystemProtocol422012.Routes[action]) ~= "table" then
            return nil, complete(action,
                GodSystemResult.fail("runtime.client", "actionUnknown", {
                    action = action,
                }), requestOptions.callback)
        end
        local requestId = tostring(requestOptions.requestId or nextId(action))
        local operationId = tostring(requestOptions.operationId or requestId)
        instance.pending[action] = {
            requestId = requestId,
            operationId = operationId,
        }
        if runtime and type(runtime.dispatch) == "function" then
            local result = runtime:dispatch({
                protocol = protocol,
                requestId = requestId,
                operationId = operationId,
                action = action,
                args = copy(type(args) == "table" and args or {}),
            }, actor())
            return complete(action, result, requestOptions.callback)
        end
        if remote and type(remote.request) == "function" then
            local id, failure = remote:request(action,
                copy(type(args) == "table" and args or {}), {
                    requestId = requestId,
                    operationId = operationId,
                    callback = function(result)
                        complete(action, result, requestOptions.callback)
                    end,
                })
            if not id then
                return nil, complete(action, failure, requestOptions.callback)
            end
            return {
                ok = true,
                code = "requestPending",
                operationId = operationId,
                moduleId = "runtime.client",
                data = { requestId = requestId, action = action },
            }
        end
        return nil, complete(action,
            GodSystemResult.fail("runtime.client", "transportUnavailable",
                nil, operationId), requestOptions.callback)
    end

    function instance:get(action)
        return copy(self.cache[tostring(action or "")])
    end

    function instance:isPending(action)
        return self.pending[tostring(action or "")] ~= nil
    end

    function instance:health()
        local pending = 0
        for _ in pairs(self.pending) do pending = pending + 1 end
        return {
            ok = self.failures == 0,
            code = self.failures == 0 and "healthy" or "degraded",
            data = {
                pending = pending,
                completed = self.completed,
                failures = self.failures,
            },
            moduleId = "runtime.client",
        }
    end

    function instance:subscribe(callback)
        assert(type(callback) == "function", "gateway observer required")
        observers[#observers + 1] = callback
        local active = true
        return function()
            if not active then return false end
            active = false
            for index = #observers, 1, -1 do
                if observers[index] == callback then
                    table.remove(observers, index)
                    return true
                end
            end
            return false
        end
    end

    return instance
end

return Gateway
