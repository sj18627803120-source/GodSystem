require "GodSystem/Core/Result"
require "GodSystem/Runtime/Payload"
require "GodSystem/Runtime/Protocol422012"

GodSystemClientGateway = GodSystemClientGateway or {}

local Gateway = GodSystemClientGateway
local Payload = GodSystemRuntimePayload

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
    local retryStoreOption = options.retryStore
    local observers = {}
    if type(onResult) == "function" then observers[1] = onResult end
    local sequence = 0
    local sessionId = Payload.identifier(options.sessionId)
        or ("session-" .. tostring(
            type(getTimestampMs) == "function" and getTimestampMs()
                or ((os.time and os.time() or 0) * 1000))
            .. "-" .. tostring(options):gsub("[^%w]", ""))
    local instance = {
        cache = {},
        pending = {},
        completed = 0,
        failures = 0,
        retry = {},
    }

    local function retryStore()
        if type(retryStoreOption) == "function" then
            local value = retryStoreOption()
            return type(value) == "table" and value or nil
        end
        return type(retryStoreOption) == "table" and retryStoreOption or nil
    end

    local function loadRetry(action)
        local store = retryStore()
        return instance.retry[action] or (store and store[action]) or nil
    end

    local function saveRetry(action, row)
        instance.retry[action] = row and copy(row) or nil
        local store = retryStore()
        if store then store[action] = row and copy(row) or nil end
    end

    local function nextId(action)
        sequence = sequence + 1
        return table.concat({
            "ui",
            sessionId,
            tostring(action or ""):gsub("[^%w%._%-]", "_"),
            tostring(sequence),
        }, ":")
    end

    local function complete(action, result, callback)
        result = GodSystemResult.normalize(result, "runtime.client")
        local row = instance.pending[action]
        local retry = loadRetry(action)
        if row and (result.code == "requestTimeout"
            or result.code == "disconnected")
        then
            saveRetry(action, {
                requestId = row.requestId,
                operationId = row.operationId,
                fingerprint = row.fingerprint,
            })
        elseif row then
            if retry and retry.operationId == row.operationId then
                saveRetry(action, nil)
            end
        elseif retry and retry.operationId == result.operationId
            and result.code ~= "requestTimeout"
            and result.code ~= "disconnected"
        then
            -- A valid response may arrive after the local timeout callback.
            -- It still completes the original operation and must retire the
            -- persisted retry identity.
            saveRetry(action, nil)
        end
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
        if instance.pending[action] then
            local value = GodSystemResult.fail("runtime.client",
                "actionPending", { action = action },
                requestOptions.operationId)
            instance.completed = instance.completed + 1
            instance.failures = instance.failures + 1
            if type(requestOptions.callback) == "function" then
                requestOptions.callback(copy(value))
            end
            for index = 1, #observers do
                observers[index](action, copy(value))
            end
            return nil, value
        end
        local requestId = tostring(requestOptions.requestId or nextId(action))
        local argsTable = copy(type(args) == "table" and args or {})
        local fingerprint, fingerprintError = Payload.fingerprint(action, argsTable)
        if not fingerprint then
            return nil, complete(action,
                GodSystemResult.fail("runtime.client", fingerprintError),
                requestOptions.callback)
        end
        local retry = loadRetry(action)
        local reuseRetry = not requestOptions.requestId
            and type(retry) == "table"
            and retry.fingerprint == fingerprint
        if reuseRetry then
            requestId = tostring(retry.requestId)
        elseif type(retry) == "table" and retry.fingerprint ~= fingerprint then
            saveRetry(action, nil)
        end
        local operationId = tostring((reuseRetry and retry.operationId)
            or requestOptions.operationId
            or requestId)
        instance.pending[action] = {
            requestId = requestId,
            operationId = operationId,
            fingerprint = fingerprint,
        }
        if runtime and type(runtime.dispatch) == "function" then
            local result = runtime:dispatch({
                protocol = protocol,
                requestId = requestId,
                operationId = operationId,
                action = action,
                args = argsTable,
            }, actor())
            return complete(action, result, requestOptions.callback)
        end
        if remote and type(remote.request) == "function" then
            local id, failure = remote:request(action,
                argsTable, {
                    requestId = requestId,
                    operationId = operationId,
                    callback = function(result)
                        complete(action, result, requestOptions.callback)
                    end,
                })
            if not id then
                return nil, complete(action, failure, requestOptions.callback)
            end
            if not instance.pending[action] then
                return copy(instance.cache[action])
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
                retryable = (function()
                    local count = 0
                    for _ in pairs(self.retry) do count = count + 1 end
                    return count
                end)(),
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
