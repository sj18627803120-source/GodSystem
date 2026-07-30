require "GodSystem/Core/Result"
require "GodSystem/Runtime/Payload"
require "GodSystem/Runtime/Protocol422012"

GodSystemServerBridge = GodSystemServerBridge or {}

local ServerBridge = GodSystemServerBridge
local Payload = GodSystemRuntimePayload
local Protocol = GodSystemProtocol422012

local function traceback(message)
    if debug and debug.traceback then return debug.traceback(tostring(message or ""), 2) end
    return tostring(message or "")
end

function ServerBridge.new(options)
    options = type(options) == "table" and options or {}
    local transport = assert(options.transport, "server bridge transport required")
    assert(type(transport.sendToClient) == "function",
        "server bridge transport.sendToClient required")
    local dispatcher = assert(options.dispatcher, "server bridge dispatcher required")
    assert(type(dispatcher.dispatch) == "function",
        "server bridge dispatcher.dispatch required")
    local actorKey = assert(options.actorKey, "server bridge actorKey required")
    assert(type(actorKey) == "function", "server bridge actorKey must be a function")
    local protocolVersion = tostring(options.protocolVersion or Protocol.Version)
    local cacheLimit = math.max(1, math.floor(tonumber(options.cacheLimit) or 512))
    local diagnostics = options.diagnostics
    local sessions = {}
    local cache = {}
    local instance = {
        requests = 0,
        executions = 0,
        replays = 0,
        rejected = 0,
    }

    local function record(issue)
        if diagnostics and type(diagnostics.record) == "function" then
            diagnostics:record(issue)
        end
    end

    local function keyFor(actor)
        local ok, value = pcall(actorKey, actor)
        value = ok and Payload.identifier(value) or nil
        return value
    end

    local function actorCache(key)
        local bucket = cache[key]
        if not bucket then
            bucket = { byRequest = {}, byOperation = {}, order = {} }
            cache[key] = bucket
        end
        return bucket
    end

    local function send(actor, command, packet)
        local ok, value = pcall(transport.sendToClient, transport, actor,
            Protocol.Module, command, Payload.copy(packet))
        if not ok or value == false then
            record({
                moduleId = "runtime.serverBridge",
                stage = "transport",
                code = "transportFailed",
                message = tostring(value),
            })
            return false, tostring(value)
        end
        return true
    end

    local function response(requestId, operationId, result)
        return {
            protocol = protocolVersion,
            requestId = requestId,
            operationId = operationId,
            result = Payload.copy(result),
        }
    end

    local function reject(actor, command, requestId, operationId, code, data)
        instance.rejected = instance.rejected + 1
        local packet = response(requestId, operationId,
            GodSystemResult.fail("runtime.serverBridge", code, data, operationId))
        send(actor, command, packet)
        return packet
    end

    local function cacheResult(bucket, row)
        bucket.byRequest[row.requestId] = row
        bucket.byOperation[row.operationId] = row
        bucket.order[#bucket.order + 1] = row
        while #bucket.order > cacheLimit do
            local removed = table.remove(bucket.order, 1)
            if bucket.byRequest[removed.requestId] == removed then
                bucket.byRequest[removed.requestId] = nil
            end
            if bucket.byOperation[removed.operationId] == removed then
                bucket.byOperation[removed.operationId] = nil
            end
        end
    end

    local function replay(actor, row, requestId)
        instance.replays = instance.replays + 1
        local packet = Payload.copy(row.packet)
        packet.requestId = requestId
        send(actor, Protocol.S2C.Response, packet)
        return packet
    end

    function instance:receive(actor, moduleName, command, packet)
        self.requests = self.requests + 1
        if tostring(moduleName or "") ~= Protocol.Module then
            return reject(actor, Protocol.S2C.Response, nil, nil,
                "moduleMismatch", { actual = tostring(moduleName or "") })
        end
        packet = type(packet) == "table" and packet or {}
        local requestId = Payload.identifier(packet.requestId)
        local operationId = Payload.identifier(packet.operationId) or requestId
        if tostring(packet.protocol or "") ~= protocolVersion then
            return reject(actor,
                command == Protocol.C2S.Hello and Protocol.S2C.Hello
                    or Protocol.S2C.Response,
                requestId, operationId, "protocolMismatch", {
                    expected = protocolVersion,
                    actual = tostring(packet.protocol or ""),
                })
        end
        local identity = keyFor(actor)
        if not identity then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                "actorInvalid")
        end
        if not requestId or not operationId then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                "requestIdRequired")
        end
        if command == Protocol.C2S.Hello then
            sessions[identity] = true
            local result = GodSystemResult.ok("runtime.serverBridge", "hello", {
                protocol = protocolVersion,
            }, operationId)
            local outgoing = response(requestId, operationId, result)
            send(actor, Protocol.S2C.Hello, outgoing)
            return outgoing
        end
        if command ~= Protocol.C2S.Request then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                "commandUnknown", { command = tostring(command or "") })
        end
        if options.requireHello ~= false and not sessions[identity] then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                "helloRequired")
        end
        local action = tostring(packet.action or "")
        if action == "" then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                "actionRequired")
        end
        local fingerprint, fingerprintError = Payload.fingerprint(action, packet.args)
        if not fingerprint then
            return reject(actor, Protocol.S2C.Response, requestId, operationId,
                fingerprintError)
        end
        local bucket = actorCache(identity)
        local existingRequest = bucket.byRequest[requestId]
        local existingOperation = bucket.byOperation[operationId]
        local existing = existingRequest or existingOperation
        if existing then
            if existing.requestId ~= requestId and existing.operationId ~= operationId then
                return reject(actor, Protocol.S2C.Response, requestId, operationId,
                    "requestMismatch")
            end
            if existing.operationId ~= operationId
                or existing.fingerprint ~= fingerprint
            then
                return reject(actor, Protocol.S2C.Response, requestId, operationId,
                    "requestMismatch")
            end
            if existing.status ~= "complete" then
                return reject(actor, Protocol.S2C.Response, requestId, operationId,
                    "requestPending")
            end
            return replay(actor, existing, requestId)
        end

        local row = {
            requestId = requestId,
            operationId = operationId,
            fingerprint = fingerprint,
            status = "processing",
        }
        cacheResult(bucket, row)
        local ok, result = xpcall(function()
            return dispatcher:dispatch({
                protocol = protocolVersion,
                requestId = requestId,
                operationId = operationId,
                action = action,
                args = Payload.copy(type(packet.args) == "table" and packet.args or {}),
            }, actor)
        end, traceback)
        if not ok then
            record({
                moduleId = "runtime.serverBridge",
                stage = "dispatch",
                code = "dispatchFailed",
                operationId = operationId,
                message = tostring(result),
            })
            result = GodSystemResult.fail("runtime.serverBridge", "dispatchFailed", {
                message = tostring(result),
            }, operationId)
        end
        result = GodSystemResult.normalize(result, "runtime.serverBridge", operationId)
        row.status = "complete"
        row.packet = response(requestId, operationId, result)
        self.executions = self.executions + 1
        send(actor, Protocol.S2C.Response, row.packet)
        return Payload.copy(row.packet)
    end

    function instance:disconnect(actor)
        local identity = keyFor(actor)
        if identity then sessions[identity] = nil end
        return identity ~= nil
    end

    function instance:status()
        local active = 0
        for _ in pairs(sessions) do active = active + 1 end
        return {
            protocol = protocolVersion,
            sessions = active,
            requests = self.requests,
            executions = self.executions,
            replays = self.replays,
            rejected = self.rejected,
        }
    end

    return instance
end

return ServerBridge
