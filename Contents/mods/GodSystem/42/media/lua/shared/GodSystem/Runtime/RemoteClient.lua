require "GodSystem/Core/Result"
require "GodSystem/Runtime/Payload"
require "GodSystem/Runtime/Protocol422012"

GodSystemRemoteClient = GodSystemRemoteClient or {}

local RemoteClient = GodSystemRemoteClient
local Payload = GodSystemRuntimePayload
local Protocol = GodSystemProtocol422012

local function defaultClock()
    return (os.time and os.time() or 0) * 1000
end

local function invoke(callback, ...)
    if type(callback) ~= "function" then return true end
    return pcall(callback, ...)
end

function RemoteClient.new(options)
    options = type(options) == "table" and options or {}
    local transport = assert(options.transport, "remote client transport required")
    assert(type(transport.sendToServer) == "function",
        "remote client transport.sendToServer required")
    local protocolVersion = tostring(options.protocolVersion or Protocol.Version)
    local now = type(options.now) == "function" and options.now or defaultClock
    local timeoutMs = math.max(1, math.floor(tonumber(options.timeoutMs) or 10000))
    local completedLimit = math.max(1, math.floor(tonumber(options.completedLimit) or 256))
    local diagnostics = options.diagnostics
    local sequence = 0
    local pending = {}
    local retryable = {}
    local completed = {}
    local completedOrder = {}
    local instance = {
        connected = false,
        serverProtocol = nil,
        sent = 0,
        received = 0,
        timedOut = 0,
        rejected = 0,
    }

    local function record(issue)
        if diagnostics and type(diagnostics.record) == "function" then
            diagnostics:record(issue)
        end
    end

    local function newRequestId()
        sequence = sequence + 1
        if type(options.nextRequestId) == "function" then
            local value = Payload.identifier(options.nextRequestId(sequence))
            if value then return value end
        end
        return "client-" .. tostring(math.floor(now())) .. "-" .. tostring(sequence)
    end

    local function remember(requestId, value)
        completed[requestId] = Payload.copy(value)
        completedOrder[#completedOrder + 1] = requestId
        while #completedOrder > completedLimit do
            completed[table.remove(completedOrder, 1)] = nil
        end
    end

    local function complete(requestId, result, packet, canRetry)
        local row = pending[requestId] or retryable[requestId]
        if not row then return false, "requestUnknown" end
        pending[requestId] = nil
        retryable[requestId] = nil
        local value = GodSystemResult.normalize(Payload.copy(result),
            "runtime.remote", row.operationId)
        if canRetry == true then
            retryable[requestId] = row
        else
            remember(requestId, value)
        end
        local ok, message = invoke(row.callback, value, Payload.copy(packet))
        if not ok then
            record({
                moduleId = "runtime.remote",
                stage = "callback",
                code = "callbackFailed",
                operationId = row.operationId,
                message = tostring(message),
            })
        end
        return true, value
    end

    local function send(command, packet)
        local ok, value = pcall(transport.sendToServer, transport,
            Protocol.Module, command, Payload.copy(packet))
        if not ok or value == false then
            return false, tostring(value)
        end
        instance.sent = instance.sent + 1
        return true
    end

    local function enqueue(command, action, args, requestOptions)
        requestOptions = type(requestOptions) == "table" and requestOptions or {}
        local requestId = Payload.identifier(requestOptions.requestId) or newRequestId()
        local operationId = Payload.identifier(requestOptions.operationId) or requestId
        local fingerprint, fingerprintError = Payload.fingerprint(action, args)
        if not fingerprint then
            return nil, GodSystemResult.fail("runtime.remote", fingerprintError,
                nil, operationId)
        end
        local existing = pending[requestId]
        if existing then
            if existing.operationId ~= operationId or existing.fingerprint ~= fingerprint then
                return nil, GodSystemResult.fail("runtime.remote", "requestMismatch",
                    nil, operationId)
            end
            existing.attempts = existing.attempts + 1
            existing.sentAt = now()
            existing.deadline = existing.sentAt + timeoutMs
            local sent, reason = send(existing.command, existing.packet)
            if not sent then
                return nil, GodSystemResult.fail("runtime.remote", "transportFailed",
                    { message = reason }, operationId)
            end
            return requestId
        end
        existing = retryable[requestId]
        if existing then
            if existing.operationId ~= operationId
                or existing.fingerprint ~= fingerprint
            then
                return nil, GodSystemResult.fail("runtime.remote",
                    "requestMismatch", nil, operationId)
            end
            retryable[requestId] = nil
            existing.callback = requestOptions.callback or existing.callback
            existing.attempts = existing.attempts + 1
            existing.sentAt = now()
            existing.deadline = existing.sentAt + timeoutMs
            pending[requestId] = existing
            local sent, reason = send(existing.command, existing.packet)
            if not sent then
                pending[requestId] = nil
                retryable[requestId] = existing
                return nil, GodSystemResult.fail("runtime.remote",
                    "transportFailed", { message = reason }, operationId)
            end
            return requestId
        end
        if completed[requestId] then
            local value = Payload.copy(completed[requestId])
            local ok, message = invoke(requestOptions.callback, value, nil)
            if not ok then
                record({
                    moduleId = "runtime.remote",
                    stage = "callback",
                    code = "callbackFailed",
                    operationId = operationId,
                    message = tostring(message),
                })
            end
            return requestId, value
        end
        local packet = {
            protocol = protocolVersion,
            requestId = requestId,
            operationId = operationId,
            action = action,
            args = Payload.copy(type(args) == "table" and args or {}),
        }
        local sentAt = now()
        pending[requestId] = {
            command = command,
            packet = packet,
            operationId = operationId,
            fingerprint = fingerprint,
            callback = requestOptions.callback,
            sentAt = sentAt,
            deadline = sentAt + timeoutMs,
            attempts = 1,
        }
        local sent, reason = send(command, packet)
        if not sent then
            pending[requestId] = nil
            return nil, GodSystemResult.fail("runtime.remote", "transportFailed",
                { message = reason }, operationId)
        end
        return requestId
    end

    function instance:hello(metadata, requestOptions)
        requestOptions = type(requestOptions) == "table" and requestOptions or {}
        return enqueue(Protocol.C2S.Hello, "runtime.hello",
            type(metadata) == "table" and metadata or {}, requestOptions)
    end

    function instance:request(action, args, requestOptions)
        action = tostring(action or "")
        if action == "" then
            return nil, GodSystemResult.fail("runtime.remote", "actionRequired")
        end
        if options.requireHello ~= false and not self.connected then
            return nil, GodSystemResult.fail("runtime.remote", "helloRequired")
        end
        return enqueue(Protocol.C2S.Request, action, args, requestOptions)
    end

    function instance:receive(moduleName, command, packet)
        if tostring(moduleName or "") ~= Protocol.Module then
            self.rejected = self.rejected + 1
            return false, "moduleMismatch"
        end
        packet = type(packet) == "table" and packet or {}
        if tostring(packet.protocol or "") ~= protocolVersion then
            self.rejected = self.rejected + 1
            return false, "protocolMismatch"
        end
        if command == Protocol.S2C.Snapshot then
            local ok, message = invoke(options.onSnapshot, Payload.copy(packet.data), packet)
            if not ok then
                record({
                    moduleId = "runtime.remote",
                    stage = "snapshot",
                    code = "callbackFailed",
                    message = tostring(message),
                })
            end
            self.received = self.received + 1
            return true
        end
        if command ~= Protocol.S2C.Hello and command ~= Protocol.S2C.Response then
            self.rejected = self.rejected + 1
            return false, "commandUnknown"
        end
        local requestId = Payload.identifier(packet.requestId)
        local row = requestId
            and (pending[requestId] or retryable[requestId]) or nil
        if not row then
            self.rejected = self.rejected + 1
            return false, "requestUnknown"
        end
        if Payload.identifier(packet.operationId) ~= row.operationId then
            self.rejected = self.rejected + 1
            return false, "operationMismatch"
        end
        self.received = self.received + 1
        local ok, result = complete(requestId, packet.result, packet)
        if ok and command == Protocol.S2C.Hello and result.ok then
            self.connected = true
            self.serverProtocol = tostring(packet.protocol)
        end
        return ok, result
    end

    function instance:poll(at)
        at = tonumber(at) or now()
        local expired = {}
        for requestId, row in pairs(pending) do
            if at >= row.deadline then expired[#expired + 1] = requestId end
        end
        table.sort(expired)
        local results = {}
        for index = 1, #expired do
            local requestId = expired[index]
            local row = pending[requestId]
            if row then
                self.timedOut = self.timedOut + 1
                local value = GodSystemResult.fail("runtime.remote", "requestTimeout", {
                    attempts = row.attempts,
                    timeoutMs = timeoutMs,
                }, row.operationId)
                complete(requestId, value, nil, true)
                results[#results + 1] = value
            end
        end
        return results
    end

    function instance:disconnect(reason)
        self.connected = false
        self.serverProtocol = nil
        local ids = {}
        for requestId in pairs(pending) do ids[#ids + 1] = requestId end
        table.sort(ids)
        for index = 1, #ids do
            local requestId = ids[index]
            local row = pending[requestId]
            if row then
                complete(requestId, GodSystemResult.fail(
                    "runtime.remote", "disconnected", {
                        reason = tostring(reason or "disconnect"),
                    }, row.operationId), nil, true)
            end
        end
        return #ids
    end

    function instance:result(requestId)
        return Payload.copy(completed[tostring(requestId or "")])
    end

    function instance:pendingCount()
        local count = 0
        for _ in pairs(pending) do count = count + 1 end
        return count
    end

    function instance:retryableCount()
        local count = 0
        for _ in pairs(retryable) do count = count + 1 end
        return count
    end

    function instance:status()
        return {
            connected = self.connected,
            protocol = protocolVersion,
            serverProtocol = self.serverProtocol,
            pending = self:pendingCount(),
            retryable = self:retryableCount(),
            sent = self.sent,
            received = self.received,
            timedOut = self.timedOut,
            rejected = self.rejected,
        }
    end

    return instance
end

return RemoteClient
